-------------------------------------------------------------------------------
-- DINO RUN 32 - Tiny Tapeout VGA-spel med EXAKT 32 lagrade bitar
-------------------------------------------------------------------------------
-- Lagrade tillståndsbitar (vippor):
--   hpos  10 bitar  VGA-kolumn  (0..799)
--   vpos  10 bitar  VGA-rad     (0..524)
--   dist   8 bitar  världens position, +1 per bildruta.
--                   Efter game over återanvänds den som timer.
--   air    4 bitar  0 = på marken, 1..14 = i luften, 15 = död (game over)
--   ------------------
--   summa 32 bitar
--
-- Allt annat (hinder, fåglar, moln, berg, mark, sol/måne, stjärnor, text,
-- ljud och kollision) räknas fram kombinatoriskt från de 32 bitarna.
--
-- Ingångar
--   ui_in(0)          paus
--   ui_in(1)          hopp  (håll in = högt hopp, kort tryck = lågt hopp)
--   ui_in(2)          figur: 0 = dinosaurie, 1 = sköldpadda
--   ui_in(3)          ducka (på marken) / snabbfall (i luften)
--   ui_in(5 downto 4) bana 0..3  (0 = lätt ... 3 = svår)
--   ui_in(6)          nattläge
--   ui_in(7)          ljud av
-- Utgångar
--   uo_out            Tiny VGA PMOD (640x480 @ 60 Hz, 25,175 MHz klocka)
--   uio_out(7)        ljud (fyrkantsvåg, t.ex. till Tiny Tapeout Audio PMOD)
--
-- Spelet ritas i 320x240 "spelpixlar" (varje spelpixel = 2x2 skärmpixlar).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tt_um_bouncing_ball is
  port (
    ui_in   : in  std_logic_vector(7 downto 0);
    uo_out  : out std_logic_vector(7 downto 0);
    uio_in  : in  std_logic_vector(7 downto 0);
    uio_out : out std_logic_vector(7 downto 0);
    uio_oe  : out std_logic_vector(7 downto 0);
    ena     : in  std_logic;
    clk     : in  std_logic;
    rst_n   : in  std_logic
  );
end entity tt_um_bouncing_ball;

architecture rtl of tt_um_bouncing_ball is

  ---------------------------------------------------------------------------
  -- VGA 640x480. Den synliga ytan ligger först (hpos 0..639, vpos 0..479),
  -- då blir skärmkoordinaten = räknaren och inga subtraktioner behövs.
  ---------------------------------------------------------------------------
  constant H_ACTIVE     : integer := 640;
  constant H_SYNC_START : integer := 656;
  constant H_SYNC_END   : integer := 752;
  constant H_TOTAL      : integer := 800;
  constant V_ACTIVE     : integer := 480;
  constant V_SYNC_START : integer := 490;
  constant V_SYNC_END   : integer := 492;
  constant V_TOTAL      : integer := 525;

  ---------------------------------------------------------------------------
  -- Spelinställningar (spelpixlar)
  ---------------------------------------------------------------------------
  constant GROUND_Y      : integer := 192;  -- första markraden
  constant PLAYER_TOP    : integer := 176;  -- figurens översta rad på marken
  constant SKY_BAND_Y    : integer := 150;  -- ljusare himmel under denna rad
  constant AIR_DEAD      : integer := 15;
  constant RESTART_DELAY : integer := 40;   -- bildrutor innan omstart tillåts

  ---------------------------------------------------------------------------
  -- Färger (RRGGBB)
  ---------------------------------------------------------------------------
  subtype rgb_t is std_logic_vector(5 downto 0);
  constant C_BLACK    : rgb_t := "000000";
  constant C_WHITE    : rgb_t := "111111";
  constant C_SKY      : rgb_t := "011011";
  constant C_SKY2     : rgb_t := "011011";
  constant C_CLOUD    : rgb_t := "111111";
  constant C_SUN      : rgb_t := "111100";
  constant C_HILL     : rgb_t := "011010";
  constant C_LINE     : rgb_t := "010100";
  constant C_SAND     : rgb_t := "111001";
  constant C_PEBBLE   : rgb_t := "100100";
  constant C_CACTUS   : rgb_t := "001000";
  constant C_BIRD     : rgb_t := "100001";
  constant C_DINO     : rgb_t := "000100";
  constant C_SHELL    : rgb_t := "100100";
  constant C_SHELL2   : rgb_t := "010000";
  constant C_SKIN     : rgb_t := "011100";
  constant C_TEXT     : rgb_t := "010101";
  constant C_N_SKY    : rgb_t := "000001";
  constant C_N_SKY2   : rgb_t := "000110";
  constant C_N_CLOUD  : rgb_t := "010101";
  constant C_N_MOON   : rgb_t := "111110";
  constant C_N_HILL   : rgb_t := "000101";
  constant C_N_LINE   : rgb_t := "101010";
  constant C_N_SAND   : rgb_t := "010100";
  constant C_N_PEBBLE : rgb_t := "000000";
  constant C_N_CACTUS : rgb_t := "001100";
  constant C_N_BIRD   : rgb_t := "110110";
  constant C_N_DINO   : rgb_t := "101010";

  ---------------------------------------------------------------------------
  -- Grafik-ROM (genererade från pixelritningar)
  ---------------------------------------------------------------------------
  subtype row16_t is std_logic_vector(15 downto 0);
  type rom16_t is array (0 to 15) of row16_t;
  type jump_t is array (0 to 31) of unsigned(5 downto 0);
  type track_t is array (0 to 15) of std_logic_vector(5 downto 0);
  type font_t is array (0 to 127) of std_logic_vector(4 downto 0);
  type circle_t is array (0 to 31) of unsigned(4 downto 0);
  type cloud_t is array (0 to 3) of unsigned(7 downto 0);

  -- Dinosaurie: kropp (rad 0..12)
  constant D_BODY : rom16_t := (
    "0000000001111110",  -- .........######.
    "0000000011011111",  -- ........##.#####
    "0000000011111111",  -- ........########
    "0000000011111111",  -- ........########
    "0000000011111000",  -- ........#####...
    "0000000011111110",  -- ........#######.
    "1000000111110000",  -- #......#####....
    "1000001111111000",  -- #.....#######...
    "1100011111010000",  -- ##...#####.#....
    "1111111111000000",  -- ##########......
    "0111111111000000",  -- .#########......
    "0011111111000000",  -- ..########......
    "0001111110000000",  -- ...######.......
    "0000000000000000",
    "0000000000000000",
    "0000000000000000"
  );

  -- Dinosaurie: ben, index = pose*4 + rad(1 downto 0)
  constant D_LEGS : rom16_t := (
    "0000000000000000",
    "0001100110000000",  -- runA rad 13: ...##..##.......
    "0001100001000000",  -- runA rad 14: ...##....#......
    "0001100001100000",  -- runA rad 15: ...##....##.....
    "0000000000000000",
    "0001100110000000",  -- runB rad 13: ...##..##.......
    "0000100001100000",  -- runB rad 14: ....#....##.....
    "0000110001100000",  -- runB rad 15: ....##...##.....
    "0000000000000000",
    "0001100110000000",  -- air rad 13: ...##..##.......
    "0001100011000000",  -- air rad 14: ...##...##......
    "0001000010000000",  -- air rad 15: ...#....#.......
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000"
  );

  -- Dinosaurie: duckar
  constant D_DUCK : rom16_t := (
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000111111",  -- ..........######
    "1000000001101111",  -- #........##.####
    "1100000111111111",  -- ##.....#########
    "1111111111111111",  -- ################
    "0111111111100000",  -- .##########.....
    "0011111111000000",  -- ..########......
    "0001100110000000",  -- ...##..##.......
    "0001000011000000"  -- ...#....##......
  );

  -- Sköldpadda: skal + huvud
  constant T_BODY : rom16_t := (
    "0000000000000000",  -- ................
    "0000000000000000",  -- ................
    "0000000000001110",  -- ............###.
    "0000000000011111",  -- ...........#####
    "0000000000011011",  -- ...........##.##
    "0000111111011111",  -- ....######.#####
    "0001111111101110",  -- ...########.###.
    "0011111111110110",  -- ..##########.##.
    "0111111111111010",  -- .############.#.
    "0111111111111100",  -- .#############..
    "1111111111111100",  -- ##############..
    "1111111111111100",  -- ##############..
    "0111111111111000",  -- .############...
    "0000000000000000",
    "0000000000000000",
    "0000000000000000"
  );

  -- Sköldpadda: ben
  constant T_LEGS : rom16_t := (
    "0000000000000000",
    "0011000000110000",  -- runA rad 13: ..##......##....
    "0011000000011000",  -- runA rad 14: ..##.......##...
    "0001100000001000",  -- runA rad 15: ...##.......#...
    "0000000000000000",
    "0001100001100000",  -- runB rad 13: ...##....##.....
    "0011000001100000",  -- runB rad 14: ..##.....##.....
    "0010000011000000",  -- runB rad 15: ..#.....##......
    "0000000000000000",
    "0011000000110000",  -- air rad 13: ..##......##....
    "0110000001100000",  -- air rad 14: .##......##.....
    "0100000001000000",  -- air rad 15: .#.......#......
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000"
  );

  -- Sköldpadda: drar in huvudet
  constant T_DUCK : rom16_t := (
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000000000000000",
    "0000111111100000",  -- ....#######.....
    "0001111111110000",  -- ...#########....
    "0011111111111000",  -- ..###########...
    "0111111111111100",  -- .#############..
    "1111111111111110",  -- ###############.
    "1111111111111110",  -- ###############.
    "0110000000110000",  -- .##.......##....
    "0110000000110000"  -- .##.......##....
  );

  -- Fågel (pterodaktyl), vingar upp (0..7) och ner (8..15)
  constant BIRD_ROM : rom16_t := (
    "0000001000000000",  -- ......#.........
    "0000001100000000",  -- ......##........
    "0010001110000000",  -- ..#...###.......
    "0110001111000000",  -- .##...####......
    "1111111111111110",  -- ###############.
    "0001111111111100",  -- ...###########..
    "0000001111000000",  -- ......####......
    "0000000000000000",  -- ................
    "0000000000000000",  -- ................
    "0010000000000000",  -- ..#.............
    "0110000000000000",  -- .##.............
    "1111111111111110",  -- ###############.
    "0001111111111100",  -- ...###########..
    "0000001111000000",  -- ......####......
    "0000001110000000",  -- ......###.......
    "0000001100000000"  -- ......##........
  );

  -- Hoppkurva: höjd (spelpixlar) för index air*2 + dist(0)
  constant JUMP_H : jump_t := (
    "000000",  -- air  0.0: 0
    "000000",  -- air  0.1: 0
    "000101",  -- air  1.0: 5
    "001010",  -- air  1.1: 10
    "001111",  -- air  2.0: 15
    "010011",  -- air  2.1: 19
    "010111",  -- air  3.0: 23
    "011010",  -- air  3.1: 26
    "011101",  -- air  4.0: 29
    "100000",  -- air  4.1: 32
    "100010",  -- air  5.0: 34
    "100100",  -- air  5.1: 36
    "100110",  -- air  6.0: 38
    "100111",  -- air  6.1: 39
    "101000",  -- air  7.0: 40
    "101000",  -- air  7.1: 40
    "101000",  -- air  8.0: 40
    "101000",  -- air  8.1: 40
    "100111",  -- air  9.0: 39
    "100110",  -- air  9.1: 38
    "100100",  -- air 10.0: 36
    "100010",  -- air 10.1: 34
    "100000",  -- air 11.0: 32
    "011101",  -- air 11.1: 29
    "011010",  -- air 12.0: 26
    "010111",  -- air 12.1: 23
    "010011",  -- air 13.0: 19
    "001111",  -- air 13.1: 15
    "001010",  -- air 14.0: 10
    "000101",  -- air 14.1: 5
    "000000",  -- air 15.0: 0
    "000000"  -- air 15.1: 0
  );

  -- Banor: typ(5..3) & ruta(2..0) för varje avsnitt
  constant TRACKS : track_t := (
    "000000",  -- bana 0 avsnitt 0: tomt
    "001100",  -- bana 0 avsnitt 1: liten kaktus i ruta 4
    "010100",  -- bana 0 avsnitt 2: stor kaktus i ruta 4
    "011011",  -- bana 0 avsnitt 3: dubbelkaktus i ruta 3
    "000000",  -- bana 1 avsnitt 0: tomt
    "010011",  -- bana 1 avsnitt 1: stor kaktus i ruta 3
    "110101",  -- bana 1 avsnitt 2: mellanhög fågel i ruta 5
    "100011",  -- bana 1 avsnitt 3: stor+liten kaktus i ruta 3
    "001111",  -- bana 2 avsnitt 0: liten kaktus i ruta 7
    "101100",  -- bana 2 avsnitt 1: låg fågel i ruta 4
    "011011",  -- bana 2 avsnitt 2: dubbelkaktus i ruta 3
    "110110",  -- bana 2 avsnitt 3: mellanhög fågel i ruta 6
    "011111",  -- bana 3 avsnitt 0: dubbelkaktus i ruta 7
    "111100",  -- bana 3 avsnitt 1: trippelkaktus i ruta 4
    "101011",  -- bana 3 avsnitt 2: låg fågel i ruta 3
    "100100"  -- bana 3 avsnitt 3: stor+liten kaktus i ruta 4
  );

  -- Text "GAME OVER", 5x7 tecken, index = tecken*8 + rad
  constant FONT_GO : font_t := (
    "01110",  -- 'G' .###.
    "10001",  -- 'G' #...#
    "10000",  -- 'G' #....
    "10111",  -- 'G' #.###
    "10001",  -- 'G' #...#
    "10001",  -- 'G' #...#
    "01110",  -- 'G' .###.
    "00000",
    "01110",  -- 'A' .###.
    "10001",  -- 'A' #...#
    "10001",  -- 'A' #...#
    "11111",  -- 'A' #####
    "10001",  -- 'A' #...#
    "10001",  -- 'A' #...#
    "10001",  -- 'A' #...#
    "00000",
    "10001",  -- 'M' #...#
    "11011",  -- 'M' ##.##
    "10101",  -- 'M' #.#.#
    "10101",  -- 'M' #.#.#
    "10001",  -- 'M' #...#
    "10001",  -- 'M' #...#
    "10001",  -- 'M' #...#
    "00000",
    "11111",  -- 'E' #####
    "10000",  -- 'E' #....
    "10000",  -- 'E' #....
    "11110",  -- 'E' ####.
    "10000",  -- 'E' #....
    "10000",  -- 'E' #....
    "11111",  -- 'E' #####
    "00000",
    "00000",  -- ' ' .....
    "00000",  -- ' ' .....
    "00000",  -- ' ' .....
    "00000",  -- ' ' .....
    "00000",  -- ' ' .....
    "00000",  -- ' ' .....
    "00000",  -- ' ' .....
    "00000",
    "01110",  -- 'O' .###.
    "10001",  -- 'O' #...#
    "10001",  -- 'O' #...#
    "10001",  -- 'O' #...#
    "10001",  -- 'O' #...#
    "10001",  -- 'O' #...#
    "01110",  -- 'O' .###.
    "00000",
    "10001",  -- 'V' #...#
    "10001",  -- 'V' #...#
    "10001",  -- 'V' #...#
    "10001",  -- 'V' #...#
    "10001",  -- 'V' #...#
    "01010",  -- 'V' .#.#.
    "00100",  -- 'V' ..#..
    "00000",
    "11111",  -- 'E' #####
    "10000",  -- 'E' #....
    "10000",  -- 'E' #....
    "11110",  -- 'E' ####.
    "10000",  -- 'E' #....
    "10000",  -- 'E' #....
    "11111",  -- 'E' #####
    "00000",
    "11110",  -- 'R' ####.
    "10001",  -- 'R' #...#
    "10001",  -- 'R' #...#
    "11110",  -- 'R' ####.
    "10100",  -- 'R' #.#..
    "10010",  -- 'R' #..#.
    "10001",  -- 'R' #...#
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000"
  );

  -- Cirkel (radie 12): halva bredden + 1 för varje |dy|
  constant CIRCLE_HW : circle_t := (
    "01101",
    "01101",
    "01101",
    "01101",
    "01100",
    "01100",
    "01011",
    "01011",
    "01010",
    "01001",
    "01000",
    "00110",
    "00100",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000",
    "00000"
  );

  -- Molnens höjd i de fyra molnrutorna
  constant CLOUD_Y : cloud_t := (
    "00011110",
    "00111000",
    "00010010",
    "00101100"
  );

  ---------------------------------------------------------------------------
  -- Hjälpfunktioner
  ---------------------------------------------------------------------------
  -- En rad (16 pixlar) av spelarfiguren.
  -- pose: 0/1 = springer (två benlägen), 2 = i luften / död, 3 = duckar
  function player_row(turtle : std_logic; pose : unsigned(1 downto 0);
                      r : unsigned(3 downto 0)) return row16_t is
  begin
    if pose = 3 then
      if turtle = '1' then
        return T_DUCK(to_integer(r));
      end if;
      return D_DUCK(to_integer(r));
    elsif r < 13 then
      if turtle = '1' then
        return T_BODY(to_integer(r));
      end if;
      return D_BODY(to_integer(r));
    else
      if turtle = '1' then
        return T_LEGS(to_integer(pose & r(1 downto 0)));
      end if;
      return D_LEGS(to_integer(pose & r(1 downto 0)));
    end if;
  end function;

  -- En kaktus med 4 pixlar bred stam på x0..x0+3 och två armar.
  -- tx = x i hinderrutan (0..31), hy = höjd över marken.
  -- Absolutbelopp utan abs() (GHDL-syntesen saknar stöd för abs på heltal)
  function iabs(x : integer range -2048 to 2047) return integer is
  begin
    if x < 0 then
      return -x;
    end if;
    return x;
  end function;

  function cactus(tx : integer range 0 to 31; hy : integer range 0 to 255;
                  x0 : integer range 3 to 24; big : boolean) return boolean is
    variable h, a0, a1, b0, b1 : integer range 0 to 31;
    variable px : boolean;
  begin
    if big then
      h := 22; a0 := 8; a1 := 16; b0 := 11; b1 := 19;
    else
      h := 14; a0 := 5; a1 := 10; b0 := 7; b1 := 12;
    end if;
    px := false;
    if tx >= x0 and tx < x0 + 4 and hy < h then
      px := not (hy = h - 1 and (tx = x0 or tx = x0 + 3));   -- rundad topp
    end if;
    if tx >= x0 - 3 and tx < x0 - 1 and hy >= a0 and hy < a1 then
      px := true;                                            -- vänster arm
    end if;
    if tx >= x0 - 3 and tx < x0 and hy >= a0 and hy < a0 + 2 then
      px := true;
    end if;
    if tx >= x0 + 5 and tx < x0 + 7 and hy >= b0 and hy < b1 then
      px := true;                                            -- höger arm
    end if;
    if tx >= x0 + 4 and tx < x0 + 7 and hy >= b0 and hy < b0 + 2 then
      px := true;
    end if;
    return px;
  end function;

  ---------------------------------------------------------------------------
  -- De 32 lagrade bitarna
  ---------------------------------------------------------------------------
  signal hpos : unsigned(9 downto 0);
  signal vpos : unsigned(9 downto 0);
  signal dist : unsigned(7 downto 0);
  signal air  : unsigned(3 downto 0);

  ---------------------------------------------------------------------------
  -- Kombinatoriska signaler
  ---------------------------------------------------------------------------
  signal h_end      : std_logic;
  signal frame_tick : std_logic;
  signal hsync      : std_logic;
  signal vsync      : std_logic;
  signal hit        : std_logic;
  signal snd        : std_logic;
  signal rgb        : rgb_t;

begin

  ---------------------------------------------------------------------------
  -- VGA-räknare och synk
  ---------------------------------------------------------------------------
  h_end      <= '1' when hpos = H_TOTAL - 1 else '0';
  frame_tick <= '1' when hpos = H_TOTAL - 1 and vpos = V_ACTIVE - 1 else '0';
  hsync      <= '0' when hpos >= H_SYNC_START and hpos < H_SYNC_END else '1';
  vsync      <= '0' when vpos >= V_SYNC_START and vpos < V_SYNC_END else '1';

  vga_counter : process(clk, rst_n)
  begin
    if rst_n = '0' then
      hpos <= (others => '0');
      vpos <= (others => '0');
    elsif rising_edge(clk) then
      if h_end = '1' then
        hpos <= (others => '0');
        if vpos = V_TOTAL - 1 then
          vpos <= (others => '0');
        else
          vpos <= vpos + 1;
        end if;
      else
        hpos <= hpos + 1;
      end if;
    end if;
  end process vga_counter;

  ---------------------------------------------------------------------------
  -- Spellogik: uppdateras en gång per bildruta (direkt efter sista synliga
  -- raden). Kollision registreras direkt på den pixel där den syns.
  --
  -- Knapparna läses en gång per bildruta, så ett tryck missas aldrig
  -- (originalets flankdetektor krävde att trycket kom exakt samma
  -- klockcykel som bildrutestarten, så hoppet fungerade nästan aldrig).
  ---------------------------------------------------------------------------
  game_logic : process(clk, rst_n)
    variable jump_btn : boolean;
    variable duck_btn : boolean;
  begin
    if rst_n = '0' then
      dist <= (others => '0');
      air  <= (others => '0');
    elsif rising_edge(clk) then
      jump_btn := ui_in(1) = '1';
      duck_btn := ui_in(3) = '1';
      if ui_in(0) = '0' then
        if frame_tick = '1' then
          if air = AIR_DEAD then
            -- Game over: dist räknar tiden. Hopp startar om efter en paus.
            if dist /= 255 then
              dist <= dist + 1;
            end if;
            if jump_btn and dist >= RESTART_DELAY then
              dist <= (others => '0');
              air  <= (others => '0');
            end if;
          else
            dist <= dist + 1;
            if air = 0 then
              if jump_btn then
                air <= to_unsigned(1, 4);
              end if;
            elsif air <= 7 and (duck_btn or (not jump_btn and air >= 4)) then
              -- Släppt hoppknapp (eller ducka) på väg upp: spegla fasen så
              -- att figuren vänder i samma höjd -> lägre hopp / snabbfall.
              air <= 15 - air;
            elsif dist(0) = '1' or duck_btn then
              if air = 14 then
                air <= (others => '0');
              else
                air <= air + 1;
              end if;
            end if;
          end if;
        elsif hit = '1' and air /= AIR_DEAD then
          air  <= to_unsigned(AIR_DEAD, 4);
          dist <= (others => '0');
        end if;
      end if;
    end if;
  end process game_logic;

  ---------------------------------------------------------------------------
  -- Pixelgrafik, kollision och ljud (helt kombinatoriskt)
  ---------------------------------------------------------------------------
  pixel_colour : process(hpos, vpos, dist, air, ui_in)
    variable vis      : boolean;
    variable lx       : unsigned(8 downto 0);
    variable ly       : unsigned(7 downto 0);
    variable alive    : boolean;
    variable night    : boolean;
    variable col      : rgb_t;
    variable scroll   : unsigned(7 downto 0);
    -- figuren
    variable h        : unsigned(5 downto 0);
    variable prow     : unsigned(8 downto 0);
    variable pr       : unsigned(3 downto 0);
    variable pc       : unsigned(3 downto 0);
    variable pose     : unsigned(1 downto 0);
    variable prowbits : row16_t;
    variable in_pbox  : boolean;
    variable p_on     : boolean;
    variable p_eye    : boolean;
    variable p_skin   : boolean;
    variable p_spot   : boolean;
    -- hinder
    variable wx       : unsigned(9 downto 0);
    variable entry    : std_logic_vector(5 downto 0);
    variable kind     : integer range 0 to 7;
    variable tx       : integer range 0 to 31;
    variable hyi      : integer range 0 to 255;
    variable bb       : integer range 0 to 15;
    variable br       : integer range 0 to 7;
    variable o_on     : boolean;
    variable o_bird   : boolean;
    variable o_eye    : boolean;
    -- bakgrund
    variable sh       : unsigned(5 downto 0);
    variable sy       : unsigned(5 downto 0);
    variable dxi      : integer range -512 to 511;
    variable dyi      : integer range -256 to 255;
    variable ady5     : unsigned(4 downto 0);
    variable ady5b    : unsigned(4 downto 0);
    variable in_disc  : boolean;
    variable in_disc2 : boolean;
    variable cx       : unsigned(8 downto 0);
    variable cyy      : unsigned(7 downto 0);
    variable ctx      : integer range 0 to 31;
    variable cty      : integer range 0 to 15;
    variable hx       : unsigned(7 downto 0);
    variable tri1     : unsigned(5 downto 0);
    variable tri2     : unsigned(3 downto 0);
    variable hill_top : unsigned(7 downto 0);
    variable gh       : unsigned(5 downto 0);
    -- text och ikoner
    variable tx9      : unsigned(8 downto 0);
    variable tcol     : integer range 0 to 7;
    variable glyph    : std_logic_vector(4 downto 0);
    variable u        : integer range -512 to 511;
    variable v        : integer range -256 to 255;
  begin
    vis   := hpos < H_ACTIVE and vpos < V_ACTIVE;
    lx    := hpos(9 downto 1);
    ly    := vpos(8 downto 1);
    alive := air /= AIR_DEAD;
    night := ui_in(6) = '1';
    hit   <= '0';
    snd   <= '0';
    col   := C_BLACK;

    -- Marken och bergen står still under game over
    if alive then
      scroll := dist;
    else
      scroll := (others => '0');
    end if;

    -------------------------------------------------------------------------
    -- Spelarfiguren (16x16) på x = 32..47
    -------------------------------------------------------------------------
    h    := JUMP_H(to_integer(air & dist(0)));
    prow := resize(ly, 9) + resize(h, 9) - PLAYER_TOP;
    pr   := prow(3 downto 0);
    pc   := lx(3 downto 0);
    in_pbox := lx(8 downto 4) = "00010" and prow < 16;
    if (not alive) or air /= 0 then
      pose := "10";
    elsif ui_in(3) = '1' then
      pose := "11";
    else
      pose := "0" & dist(2);
    end if;
    prowbits := player_row(ui_in(2), pose, pr);
    p_on := in_pbox and prowbits(15 - to_integer(pc)) = '1';

    p_eye := false;
    if in_pbox then
      if ui_in(2) = '0' then
        if not alive then
          p_eye := (pr = 1 and pc = 10) or ((pr = 0 or pr = 2) and (pc = 9 or pc = 11));
        elsif pose = 3 then
          p_eye := pr = 9 and pc = 11;
        else
          p_eye := pr = 1 and pc = 10;
        end if;
      else
        if not alive then
          p_eye := (pr = 4 and pc = 13) or ((pr = 3 or pr = 5) and (pc = 12 or pc = 14));
        elsif pose /= 3 then
          p_eye := pr = 4 and pc = 13;
        end if;
      end if;
    end if;
    if pose = 3 then
      p_skin := pr >= 14;
    else
      p_skin := (pc >= 11 and pr <= 8) or pr >= 13;
    end if;
    p_spot := (pr(1 downto 0) + pc(1 downto 0)) = 0 and pr >= 6 and pr <= 12;

    -------------------------------------------------------------------------
    -- Hinder. Världen är 1024 spelpixlar lång och rullar 4 pixlar/bildruta.
    -- Den delas i 4 avsnitt om 256 pixlar; varje avsnitt har ett hinder
    -- (typ + position) från banans tabell.
    -------------------------------------------------------------------------
    wx    := resize(lx, 10) + (scroll & "00");
    entry := TRACKS(to_integer(unsigned(ui_in(5 downto 4)) & wx(9 downto 8)));
    kind  := to_integer(unsigned(entry(5 downto 3)));
    tx    := to_integer(wx(4 downto 0));
    hyi   := to_integer(to_unsigned(GROUND_Y - 1, 8) - ly);
    o_on   := false;
    o_bird := false;
    o_eye  := false;
    if alive and kind /= 0 and wx(7 downto 5) = unsigned(entry(2 downto 0)) and ly < GROUND_Y then
      case kind is
        when 1 =>
          o_on := cactus(tx, hyi, 14, false);
        when 2 =>
          o_on := cactus(tx, hyi, 14, true);
        when 3 =>
          o_on := cactus(tx, hyi, 7, false) or cactus(tx, hyi, 20, false);
        when 4 =>
          o_on := cactus(tx, hyi, 8, true) or cactus(tx, hyi, 21, false);
        when 7 =>
          o_on := cactus(tx, hyi, 4, false) or cactus(tx, hyi, 14, true) or cactus(tx, hyi, 24, false);
        when others =>
          -- 5 = låg fågel (hoppa), 6 = mellanhög fågel (ducka eller hoppa)
          if kind = 5 then
            bb := 2;
          else
            bb := 12;
          end if;
          if tx < 16 and hyi >= bb and hyi < bb + 8 then
            br := bb + 7 - hyi;
            o_on   := BIRD_ROM(to_integer(dist(3) & to_unsigned(br, 3)))(15 - tx) = '1';
            o_bird := true;
            o_eye  := tx = 2 and ((dist(3) = '0' and br = 3) or (dist(3) = '1' and br = 2));
          end if;
      end case;
    end if;

    -- Kollision: en synlig pixel som tillhör både figuren och ett hinder
    if vis and alive and p_on and o_on and ui_in(0) = '0' then
      hit <= '1';
    end if;

    if vis then
      -----------------------------------------------------------------------
      -- Himmel (vit blixt när man dör), stjärnor, sol/måne
      -----------------------------------------------------------------------
      if (not alive) and dist < 3 then
        col := C_WHITE;
      elsif night then
        if ly >= SKY_BAND_Y then
          col := C_N_SKY2;
        else
          col := C_N_SKY;
        end if;
        -- stjärnor: en enkel hash av 8x8-rutans koordinater
        sy := '0' & ly(7 downto 3);
        sh := (lx(8 downto 3) + sy + (sy(4 downto 0) & '0'))
              xor ('0' & lx(8 downto 4)) xor (sy(3 downto 0) & "00");
        if lx(2 downto 0) = "011" and ly(2 downto 0) = "101" and ly < SKY_BAND_Y and
           (sh = 37 or sh = 11 or (sh = 50 and dist(5) = '1')) then
          col := C_WHITE;
        end if;
      else
        if ly >= SKY_BAND_Y then
          col := C_SKY2;
        else
          col := C_SKY;
        end if;
      end if;

      dxi := to_integer(lx) - 272;
      dyi := to_integer(ly) - 32;
      if dxi > -16 and dxi < 16 and dyi > -16 and dyi < 16 then
        -- index alltid inom tabellen (5 bitar), även när raden inte används
        ady5  := resize(to_unsigned(iabs(dyi), 9), 5);
        ady5b := resize(to_unsigned(iabs(dyi + 3), 9), 5);
        in_disc  := iabs(dxi) < to_integer(CIRCLE_HW(to_integer(ady5)));
        in_disc2 := iabs(dxi - 6) < to_integer(CIRCLE_HW(to_integer(ady5b)));
        if night then
          if in_disc and not in_disc2 then
            col := C_N_MOON;
          end if;
        elsif in_disc then
          col := C_SUN;
        end if;
      end if;

      -----------------------------------------------------------------------
      -- Moln (halva markfarten, fortsätter driva under game over)
      -----------------------------------------------------------------------
      cx := lx + (dist & '0');
      if cx(6 downto 5) = "01" then
        cyy := ly - CLOUD_Y(to_integer(cx(8 downto 7)));
        if cyy < 10 then
          ctx := to_integer(cx(4 downto 0));
          cty := to_integer(cyy(3 downto 0));
          if (cty >= 6 and ctx >= 1 and ctx <= 30 and not (cty = 9 and (ctx < 3 or ctx > 28))) or
             (cty >= 3 and cty < 6 and ctx >= 6 and ctx <= 25) or
             (cty < 3 and ctx >= 10 and ctx <= 21 and not (cty = 0 and (ctx < 12 or ctx > 19))) then
            if night then
              col := C_N_CLOUD;
            else
              col := C_CLOUD;
            end if;
          end if;
        end if;
      end if;

      -----------------------------------------------------------------------
      -- Berg i bakgrunden (en fjärdedel av markfarten)
      -----------------------------------------------------------------------
      hx := lx(7 downto 0) + scroll;
      if hx(6) = '1' then
        tri1 := not hx(5 downto 0);
      else
        tri1 := hx(5 downto 0);
      end if;
      if hx(4) = '1' then
        tri2 := not hx(3 downto 0);
      else
        tri2 := hx(3 downto 0);
      end if;
      hill_top := to_unsigned(184, 8) - tri1(5 downto 2) - tri2(3 downto 2);
      if ly >= hill_top and ly < GROUND_Y then
        if night then
          col := C_N_HILL;
        else
          col := C_HILL;
        end if;
      end if;

      -----------------------------------------------------------------------
      -- Marken: linje med små gupp, sand med småsten
      -----------------------------------------------------------------------
      gh := wx(9 downto 4);
      if ly = GROUND_Y or (ly = GROUND_Y - 1 and wx(5 downto 3) = "101" and wx(7) = '1') then
        if night then
          col := C_N_LINE;
        else
          col := C_LINE;
        end if;
      elsif ly > GROUND_Y then
        if night then
          col := C_N_SAND;
        else
          col := C_SAND;
        end if;
        if ly(1 downto 0) = "10" and wx(2 downto 1) = "00" and
           (gh(4 downto 0) xor ly(6 downto 2)) = "10110" then
          if night then
            col := C_N_PEBBLE;
          else
            col := C_PEBBLE;
          end if;
        end if;
      end if;

      -----------------------------------------------------------------------
      -- Hinder och figur
      -----------------------------------------------------------------------
      if o_on then
        if o_bird then
          if night then
            col := C_N_BIRD;
          else
            col := C_BIRD;
          end if;
        elsif night then
          col := C_N_CACTUS;
        else
          col := C_CACTUS;
        end if;
        if o_eye then
          col := C_BLACK;
        end if;
      end if;

      if p_on then
        if ui_in(2) = '0' then
          if night then
            col := C_N_DINO;
          else
            col := C_DINO;
          end if;
        elsif p_skin then
          col := C_SKIN;
        elsif p_spot then
          col := C_SHELL2;
        else
          col := C_SHELL;
        end if;
      end if;
      if p_eye then
        col := C_BLACK;
      end if;

      -----------------------------------------------------------------------
      -- Game over: text + blinkande "spela"-symbol när omstart är tillåten
      -----------------------------------------------------------------------
      if not alive then
        tx9 := lx - 91;
        if ly(7 downto 4) = "0101" and ly(3 downto 1) /= "111" and tx9 < 144 then
          tcol := to_integer(tx9(3 downto 1));
          if tcol < 5 then
            glyph := FONT_GO(to_integer(tx9(7 downto 4) & ly(3 downto 1)));
            if glyph(4 - tcol) = '1' then
              if night then
                col := C_WHITE;
              else
                col := C_TEXT;
              end if;
            end if;
          end if;
        end if;
        u := to_integer(lx) - 153;
        v := to_integer(ly) - 104;
        if dist >= RESTART_DELAY and dist(4) = '1' and u >= 0 and u < 14 and v >= 0 and v < 16 then
          if iabs(2 * v - 15) <= 15 - u then
            if night then
              col := C_WHITE;
            else
              col := C_TEXT;
            end if;
          end if;
        end if;
      end if;

      -- Paus-symbol
      if ui_in(0) = '1' and ly >= 20 and ly < 40 and
         ((lx >= 150 and lx < 156) or (lx >= 164 and lx < 170)) then
        if night then
          col := C_WHITE;
        else
          col := C_TEXT;
        end if;
      end if;
    end if;

    rgb <= col;

    -------------------------------------------------------------------------
    -- Ljud: toner från VGA-radräknaren (vpos(k) = 31,5 kHz / 2^(k+1))
    -------------------------------------------------------------------------
    if ui_in(7) = '0' and ui_in(0) = '0' then
      if alive then
        if air = 1 then
          snd <= vpos(5);                 -- hopp: stigande "pip"
        elsif air = 2 then
          snd <= vpos(4);
        elsif air = 3 then
          snd <= vpos(3);
        elsif dist(7 downto 2) = 0 then
          snd <= vpos(2);                 -- nytt varv på banan
        end if;
      elsif dist < 8 then
        snd <= vpos(4);                   -- krock: fallande ton
      elsif dist < 16 then
        snd <= vpos(5);
      elsif dist < 24 then
        snd <= vpos(6);
      end if;
    end if;
  end process pixel_colour;

  ---------------------------------------------------------------------------
  -- Tiny VGA PMOD:
  --   uo_out(7) = HSYNC, (6) = B0, (5) = G0, (4) = R0,
  --   uo_out(3) = VSYNC, (2) = B1, (1) = G1, (0) = R1
  ---------------------------------------------------------------------------
  uo_out <= hsync & rgb(0) & rgb(2) & rgb(4) & vsync & rgb(1) & rgb(3) & rgb(5);

  -- Ljud på uio_out(7), övriga dubbelriktade pinnar oanvända
  uio_out <= snd & "0000000";
  uio_oe  <= "10000000";

end architecture rtl;
