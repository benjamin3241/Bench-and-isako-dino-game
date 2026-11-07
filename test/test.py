# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0
#
# Test för DINO RUN 32 (VGA 640x480 @ 60 Hz, Tiny VGA PMOD på uo_out).
# Kontrollerar HSYNC/VSYNC-timing, att en bild ritas och att hoppet fungerar.

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

H_TOTAL = 800
H_SYNC = 96
V_TOTAL = 525
FRAME = H_TOTAL * V_TOTAL

GATES = os.environ.get("GATES") == "yes"


def val(sig):
    """Signalvärde som heltal (0 om det innehåller X/Z)."""
    v = sig.value
    try:
        return v.to_unsigned()
    except AttributeError:
        try:
            return int(v)
        except ValueError:
            return 0
    except ValueError:
        return 0


def sync(dut):
    uo = val(dut.uo_out)
    return (uo >> 7) & 1, (uo >> 3) & 1, uo & 0x77


async def reset(dut, ui=0):
    dut.ena.value = 1
    dut.ui_in.value = ui
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1


async def find_vsync_fall(dut, limit):
    prev = None
    for i in range(limit):
        await RisingEdge(dut.clk)
        _, vs, _ = sync(dut)
        if prev == 1 and vs == 0:
            return i
        prev = vs
    return None


@cocotb.test()
async def test_vga_timing_and_picture(dut):
    clock = Clock(dut.clk, 40, unit="ns")       # ~25 MHz pixelklocka
    cocotb.start_soon(clock.start())
    await reset(dut)

    # --- HSYNC: period 800, puls 96, och synliga färger på raderna
    falls, widths, colour_px, blank_bad = [], [], 0, 0
    prev_hs, low_at, cyc_since_fall = None, None, None   # ingen falsk flank efter reset
    for cyc in range(H_TOTAL * 60):
        await RisingEdge(dut.clk)
        hs, vs, rgb = sync(dut)
        if prev_hs == 1 and hs == 0:
            falls.append(cyc)
            low_at = cyc
            cyc_since_fall = 0
        if prev_hs == 0 and hs == 1 and low_at is not None:
            widths.append(cyc - low_at)
        if cyc_since_fall is not None:
            # synlig del: 144..783 cykler efter HSYNC-flanken
            if 144 + 2 <= cyc_since_fall < 784 - 2:
                if rgb:
                    colour_px += 1
            elif cyc_since_fall > 784 + 2 or 2 < cyc_since_fall < 144 - 2:
                if rgb:
                    blank_bad += 1
            cyc_since_fall += 1
        prev_hs = hs

    periods = [b - a for a, b in zip(falls, falls[1:])]
    dut._log.info(f"HSYNC-perioder {set(periods)}, pulsbredd {set(widths)}")
    assert periods and all(p == H_TOTAL for p in periods), "fel HSYNC-period"
    assert widths and all(w == H_SYNC for w in widths), "fel HSYNC-pulsbredd"
    assert colour_px > 1000, "ingen bild ritas (bara svart)"
    assert blank_bad == 0, "färg utanför synlig yta"
    assert val(dut.uio_oe) == 0x80, "uio_oe ska vara 0x80 (ljud på uio[7])"

    if GATES:
        return      # resten är för långsamt på grindnivå

    # --- VSYNC: en hel bildruta = 800 * 525 klockcykler
    await find_vsync_fall(dut, FRAME + 10)
    await ClockCycles(dut.clk, FRAME - 6)
    i = await find_vsync_fall(dut, 12)
    assert i is not None and i == 5, f"fel VSYNC-period (avvikelse {i})"
    dut._log.info("VSYNC-period OK (420000 cykler)")


@cocotb.test(skip=GATES)
async def test_jump(dut):
    """Hoppknappen (ui_in[1]) ska få figuren att lämna marken."""
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    await ClockCycles(dut.clk, 2 * FRAME)       # två bildrutor på marken
    dut.ui_in.value = 0b10                      # håll in hopp
    await ClockCycles(dut.clk, 6 * FRAME)
    dut.ui_in.value = 0

    # Figuren står på x = 64..95 (skärmpixlar). Leta efter dinosaurie-färg
    # (G0 = 1, övrigt 0 -> uo_out & 0x77 == 0x20) högre upp än vanligt.
    top_line, line, cyc_since_fall, prev_hs = None, -1, None, None
    found_vs = await find_vsync_fall(dut, FRAME + 10)
    assert found_vs is not None
    for cyc in range(H_TOTAL * 420):
        await RisingEdge(dut.clk)
        hs, vs, rgb = sync(dut)
        if prev_hs == 1 and hs == 0:
            line += 1
            cyc_since_fall = 0
        if cyc_since_fall is not None:
            x = cyc_since_fall - 144
            if 64 <= x < 96 and rgb == 0x20 and top_line is None:
                top_line = line - 35
            cyc_since_fall += 1
        prev_hs = hs
    dut._log.info(f"figurens översta rad: {top_line} (på marken: 352)")
    assert top_line is not None and top_line < 340, "figuren hoppade inte"
