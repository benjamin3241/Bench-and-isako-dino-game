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
end entity;

architecture rtl of tt_um_bouncing_ball is
  constant H_ACTIVE_START : integer := 144;
  constant H_ACTIVE_END   : integer := 784;
  constant H_TOTAL        : integer := 800;
  constant V_ACTIVE_START : integer := 35;
  constant V_ACTIVE_END   : integer := 515;
  constant V_TOTAL        : integer := 525;
  constant GROUND_Y : integer := 192; constant PLAYER_TOP : integer := 176;
  constant SKY_BAND_Y : integer := 150; constant AIR_DEAD : integer := 15;
  constant RESTART_DELAY : integer := 40;

  subtype rgb_t is std_logic_vector(5 downto 0);
  constant C_BLACK:rgb_t:="000000"; constant C_WHITE:rgb_t:="111111";
  constant C_SKY:rgb_t:="011011";
  constant C_CLOUD:rgb_t:="111111"; constant C_SUN:rgb_t:="111100";
  constant C_HILL:rgb_t:="011010"; constant C_LINE:rgb_t:="010100";
  constant C_SAND:rgb_t:="111001"; constant C_PEBBLE:rgb_t:="100100";
  constant C_CACTUS:rgb_t:="001000"; constant C_BIRD:rgb_t:="100001";
  constant C_DINO:rgb_t:="000100"; constant C_SHELL:rgb_t:="100100";
  constant C_SHELL2:rgb_t:="010000"; constant C_SKIN:rgb_t:="011100";
  constant C_TEXT:rgb_t:="010101"; constant C_N_SKY:rgb_t:="000001";
  constant C_N_SKY2:rgb_t:="000110"; constant C_N_CLOUD:rgb_t:="010101";
  constant C_N_MOON:rgb_t:="111110"; constant C_N_HILL:rgb_t:="000101";
  constant C_N_LINE:rgb_t:="101010"; constant C_N_SAND:rgb_t:="010100";
  constant C_N_PEBBLE:rgb_t:="000000"; constant C_N_CACTUS:rgb_t:="001100";
  constant C_N_BIRD:rgb_t:="110110"; constant C_N_DINO:rgb_t:="101010";

  subtype row16_t is std_logic_vector(15 downto 0);
  type rom16_t is array(0 to 15) of row16_t;
  type jump_t is array(0 to 31) of unsigned(5 downto 0);
  type track_t is array(0 to 15) of std_logic_vector(5 downto 0);
  type font_t is array(0 to 127) of std_logic_vector(4 downto 0);
  type circle_t is array(0 to 31) of unsigned(4 downto 0);
  type cloud_t is array(0 to 3) of unsigned(7 downto 0);

  constant D_BODY:rom16_t:=(
    "0000000001111110","0000000011011111","0000000011111111","0000000011111111",
    "0000000011111000","0000000011111110","1000000111110000","1000001111111000",
    "1100011111010000","1111111111000000","0111111111000000","0011111111000000",
    "0001111110000000","0000000000000000","0000000000000000","0000000000000000");
  constant D_LEGS:rom16_t:=(
    "0000000000000000","0001100110000000","0001100001000000","0001100001100000",
    "0000000000000000","0001100110000000","0000100001100000","0000110001100000",
    "0000000000000000","0001100110000000","0001100011000000","0001000010000000",
    "0000000000000000","0000000000000000","0000000000000000","0000000000000000");
  constant D_DUCK:rom16_t:=(
    "0000000000000000","0000000000000000","0000000000000000","0000000000000000",
    "0000000000000000","0000000000000000","0000000000000000","0000000000000000",
    "0000000000111111","1000000001101111","1100000111111111","1111111111111111",
    "0111111111100000","0011111111000000","0001100110000000","0001000011000000");
  constant T_BODY:rom16_t:=(
    "0000000000000000","0000000000000000","0000000000001110","0000000000011111",
    "0000000000011011","0000111111011111","0001111111101110","0011111111110110",
    "0111111111111010","0111111111111100","1111111111111100","1111111111111100",
    "0111111111111000","0000000000000000","0000000000000000","0000000000000000");
  constant T_LEGS:rom16_t:=(
    "0000000000000000","0011000000110000","0011000000011000","0001100000001000",
    "0000000000000000","0001100001100000","0011000001100000","0010000011000000",
    "0000000000000000","0011000000110000","0110000001100000","0100000001000000",
    "0000000000000000","0000000000000000","0000000000000000","0000000000000000");
  constant T_DUCK:rom16_t:=(
    "0000000000000000","0000000000000000","0000000000000000","0000000000000000",
    "0000000000000000","0000000000000000","0000000000000000","0000000000000000",
    "0000111111100000","0001111111110000","0011111111111000","0111111111111100",
    "1111111111111110","1111111111111110","0110000000110000","0110000000110000");
  constant BIRD_ROM:rom16_t:=(
    "0000001000000000","0000001100000000","0010001110000000","0110001111000000",
    "1111111111111110","0001111111111100","0000001111000000","0000000000000000",
    "0000000000000000","0010000000000000","0110000000000000","1111111111111110",
    "0001111111111100","0000001111000000","0000001110000000","0000001100000000");

  constant JUMP_H:jump_t:=(
    "000000","000000","000101","001010","001111","010011","010111","011010",
    "011101","100000","100010","100100","100110","100111","101000","101000",
    "101000","101000","100111","100110","100100","100010","100000","011101",
    "011010","010111","010011","001111","001010","000101","000000","000000");
  constant TRACKS:track_t:=(
    "000000","001100","010100","011011","000000","010011","110101","100011",
    "001111","101100","011011","110110","011111","111100","101011","100100");
  constant FONT_GO:font_t:=(
    "01110","10001","10000","10111","10001","10001","01110","00000",
    "01110","10001","10001","11111","10001","10001","10001","00000",
    "10001","11011","10101","10101","10001","10001","10001","00000",
    "11111","10000","10000","11110","10000","10000","11111","00000",
    "00000","00000","00000","00000","00000","00000","00000","00000",
    "01110","10001","10001","10001","10001","10001","01110","00000",
    "10001","10001","10001","10001","10001","01010","00100","00000",
    "11111","10000","10000","11110","10000","10000","11111","00000",
    "11110","10001","10001","11110","10100","10010","10001","00000",
    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000",    "00000");
  constant CIRCLE_HW:circle_t:=(
    "01101","01101","01101","01101","01100","01100","01011","01011",
    "01010","01001","01000","00110","00100","00000","00000","00000",
    "00000","00000","00000","00000","00000","00000","00000","00000",
    "00000","00000","00000","00000","00000","00000","00000","00000");
  constant CLOUD_Y:cloud_t:=("00011110","00111000","00010010","00101100");

  function player_row(turtle:std_logic; pose:unsigned(1 downto 0); r:unsigned(3 downto 0)) return row16_t is
  begin
    if pose=3 then if turtle='1' then return T_DUCK(to_integer(r)); end if; return D_DUCK(to_integer(r));
    elsif r<13 then if turtle='1' then return T_BODY(to_integer(r)); end if; return D_BODY(to_integer(r));
    else if turtle='1' then return T_LEGS(to_integer(pose & r(1 downto 0))); end if;
      return D_LEGS(to_integer(pose & r(1 downto 0)));
    end if;
  end function;

  function cactus(tx:integer range 0 to 31; hy:integer range 0 to 255;
                  x0:integer range 3 to 24; big:boolean) return boolean is
    variable h,a0,a1,b0,b1:integer range 0 to 31;
    variable stem,left_arm,right_arm:boolean;
  begin
    if big then h:=22;a0:=8;a1:=16;b0:=11;b1:=19; else h:=14;a0:=5;a1:=10;b0:=7;b1:=12; end if;
    stem:=tx>=x0 and tx<x0+4 and hy<h and not(hy=h-1 and (tx=x0 or tx=x0+3));
    left_arm:=tx>=x0-3 and tx<x0 and hy>=a0 and
              ((tx<x0-1 and hy<a1) or hy<a0+2);
    right_arm:=tx>=x0+4 and tx<x0+7 and hy>=b0 and
               ((tx>=x0+5 and hy<b1) or hy<b0+2);
    return stem or left_arm or right_arm;
  end function;

  signal hpos:unsigned(9 downto 0); signal vpos:unsigned(9 downto 0);
  signal distance:unsigned(7 downto 0); signal air:unsigned(3 downto 0);
  signal h_end,frame_tick,hsync,vsync,hit,snd:std_logic;
  signal hpos_stage1:unsigned(9 downto 0); signal vpos_stage1:unsigned(9 downto 0);
  signal distance_stage1:unsigned(7 downto 0); signal air_stage1:unsigned(3 downto 0);
  signal ui_in_stage1:std_logic_vector(7 downto 0);
  signal hsync_stage1,vsync_stage1:std_logic;
  signal base_rgb_comb,object_rgb_comb,player_rgb_comb,late_rgb_comb:rgb_t;
  signal object_on_comb,player_on_comb,player_eye_comb,late_on_comb:std_logic;
  signal base_rgb_q,object_rgb_q,player_rgb_q,late_rgb_q:rgb_t;
  signal object_on_q,player_on_q,player_eye_q,late_on_q:std_logic;
  signal hsync_q,vsync_q,snd_q:std_logic;
  signal rgb:rgb_t;
begin
  -- Standard VGA timing: sync pulse first, then back porch and visible area.
  h_end<='1' when hpos=H_TOTAL-1 else '0';
  frame_tick<='1' when hpos=H_TOTAL-1 and vpos=V_TOTAL-1 else '0';
  hsync<='0' when hpos<96 else '1';
  vsync<='0' when vpos<2 else '1';

  vga_counter:process(clk,rst_n)
  begin
    if rst_n='0' then hpos<=(others=>'0');vpos<=(others=>'0');
    elsif rising_edge(clk) then
      if h_end='1' then hpos<=(others=>'0'); if vpos=V_TOTAL-1 then vpos<=(others=>'0'); else vpos<=vpos+1; end if;
      else hpos<=hpos+1; end if;
    end if;
  end process;

  game_logic:process(clk,rst_n) variable jump_btn,duck_btn:boolean;
  begin
    if rst_n='0' then distance<=(others=>'0');air<=(others=>'0');
    elsif rising_edge(clk) then
      jump_btn:=ui_in(1)='1'; duck_btn:=ui_in(3)='1';
      if ui_in(0)='0' then
        if frame_tick='1' then
          if air=AIR_DEAD then
            if distance/=255 then distance<=distance+1; end if;
            if jump_btn and distance>=RESTART_DELAY then distance<=(others=>'0');air<=(others=>'0'); end if;
          else
            distance<=distance+1;
            if air=0 then if jump_btn then air<=to_unsigned(1,4); end if;
            elsif air<=7 and (duck_btn or (not jump_btn and air>=4)) then air<=15-air;
            elsif distance(0)='1' or duck_btn then if air=14 then air<=(others=>'0'); else air<=air+1; end if;
            end if;
          end if;
        elsif hit='1' and air/=AIR_DEAD then air<=to_unsigned(AIR_DEAD,4);distance<=(others=>'0'); end if;
      end if;
    end if;
  end process;

  pixel_colour:process(hpos_stage1,vpos_stage1,distance_stage1,air_stage1,ui_in_stage1)
    variable vis,alive,night:boolean; variable lx:unsigned(8 downto 0); variable ly:unsigned(7 downto 0);
    variable col,obj_col,player_col,late_col:rgb_t; variable late_on:boolean;
    variable scroll:unsigned(7 downto 0);
    variable h:unsigned(5 downto 0); variable prow:unsigned(8 downto 0);
    variable pr,pc:unsigned(3 downto 0); variable pose:unsigned(1 downto 0); variable prowbits:row16_t;
    variable in_pbox,p_on,p_eye,p_skin,p_spot:boolean;
    variable wx:unsigned(9 downto 0); variable entry:std_logic_vector(5 downto 0);
    variable kind:integer range 0 to 7; variable tx:integer range 0 to 31; variable hyi:integer range 0 to 255;
    variable bb:integer range 0 to 15; variable br:integer range 0 to 7; variable o_on,o_bird,o_eye:boolean;
    variable sh,sy:unsigned(5 downto 0); variable dxi:integer range -512 to 511; variable dyi:integer range -256 to 255;
    variable ady,ady2,disc_hw,disc2_hw:integer range 0 to 31; variable in_disc,in_disc2:boolean;
    variable cx:unsigned(8 downto 0); variable cyy:unsigned(7 downto 0); variable ctx:integer range 0 to 31;
    variable cty:integer range 0 to 15; variable hx:unsigned(7 downto 0); variable tri1:unsigned(5 downto 0);
    variable tri2:unsigned(3 downto 0); variable hill_top:unsigned(7 downto 0); variable gh:unsigned(5 downto 0);
    variable tx9:unsigned(8 downto 0); variable tcol:integer range 0 to 7; variable glyph:std_logic_vector(4 downto 0);
    variable u:integer range -512 to 511; variable v:integer range -256 to 255; variable play_y2:integer range -31 to 31;
  begin
        vis:=hpos_stage1>=H_ACTIVE_START and hpos_stage1<H_ACTIVE_END and
          vpos_stage1>=V_ACTIVE_START and vpos_stage1<V_ACTIVE_END;
    if vis then
       lx:=resize(shift_right(hpos_stage1-to_unsigned(H_ACTIVE_START,10),1),9);
       ly:=resize(shift_right(vpos_stage1-to_unsigned(V_ACTIVE_START,10),1),8);
    else
      lx:=(others=>'0');
      ly:=(others=>'0');
    end if;
    alive:=air_stage1/=AIR_DEAD; night:=ui_in_stage1(6)='1'; hit<='0';snd<='0';col:=C_BLACK;
    obj_col:=C_BLACK;player_col:=C_BLACK;late_col:=C_BLACK;late_on:=false;
    ady:=0;ady2:=0;disc_hw:=0;disc2_hw:=0;in_disc:=false;in_disc2:=false;play_y2:=0;
    if alive then scroll:=distance_stage1; else scroll:=(others=>'0'); end if;

    h:=JUMP_H(to_integer(air_stage1 & distance_stage1(0))); prow:=resize(ly,9)+resize(h,9)-PLAYER_TOP;
    pr:=prow(3 downto 0);pc:=lx(3 downto 0);in_pbox:=lx(8 downto 4)="00010" and prow<16;
    if not alive or air_stage1/=0 then pose:="10"; elsif ui_in_stage1(3)='1' then pose:="11"; else pose:="0" & distance_stage1(2); end if;
    prowbits:=player_row(ui_in_stage1(2),pose,pr);p_on:=in_pbox and prowbits(15-to_integer(pc))='1';
    p_eye:=false;
    if in_pbox then
      if ui_in_stage1(2)='0' then
        if not alive then p_eye:=(pr=1 and pc=10) or ((pr=0 or pr=2) and (pc=9 or pc=11));
        elsif pose=3 then p_eye:=pr=9 and pc=11; else p_eye:=pr=1 and pc=10; end if;
      else
        if not alive then p_eye:=(pr=4 and pc=13) or ((pr=3 or pr=5) and (pc=12 or pc=14));
        elsif pose/=3 then p_eye:=pr=4 and pc=13; end if;
      end if;
    end if;
    if pose=3 then p_skin:=pr>=14; else p_skin:=(pc>=11 and pr<=8) or pr>=13; end if;
    p_spot:=(pr(1 downto 0)+pc(1 downto 0))=0 and pr>=6 and pr<=12;

    wx:=resize(lx,10)+(scroll & "00");
    entry:=TRACKS(to_integer(unsigned(ui_in_stage1(5 downto 4)) & wx(9 downto 8)));
    kind:=to_integer(unsigned(entry(5 downto 3)));tx:=to_integer(wx(4 downto 0));
    hyi:=to_integer(to_unsigned(GROUND_Y-1,8)-ly);o_on:=false;o_bird:=false;o_eye:=false;
    if alive and kind/=0 and wx(7 downto 5)=unsigned(entry(2 downto 0)) and ly<GROUND_Y then
      case kind is
        when 1=>o_on:=cactus(tx,hyi,14,false); when 2=>o_on:=cactus(tx,hyi,14,true);
        when 3=>o_on:=cactus(tx,hyi,7,false) or cactus(tx,hyi,20,false);
        when 4=>o_on:=cactus(tx,hyi,8,true) or cactus(tx,hyi,21,false);
        when 7=>o_on:=cactus(tx,hyi,4,false) or cactus(tx,hyi,14,true) or cactus(tx,hyi,24,false);
        when others=>
          if kind=5 then bb:=2; else bb:=12; end if;
          if tx<16 and hyi>=bb and hyi<bb+8 then
            br:=bb+7-hyi;o_on:=BIRD_ROM(to_integer(distance_stage1(3) & to_unsigned(br,3)))(15-tx)='1';o_bird:=true;
            o_eye:=tx=2 and ((distance_stage1(3)='0' and br=3) or (distance_stage1(3)='1' and br=2));
          end if;
      end case;
    end if;
    if vis and alive and p_on and o_on and ui_in_stage1(0)='0' then hit<='1'; end if;

    if vis then
      if not alive and distance_stage1<3 then col:=C_WHITE;
      elsif night then
        if ly>=SKY_BAND_Y then col:=C_N_SKY2; else col:=C_N_SKY; end if;
        sy:='0' & ly(7 downto 3);
        sh:=(lx(8 downto 3)+sy+(sy(4 downto 0)&'0')) xor ('0'&lx(8 downto 4)) xor (sy(3 downto 0)&"00");
        if lx(2 downto 0)="011" and ly(2 downto 0)="101" and ly<SKY_BAND_Y and
          (sh=37 or sh=11 or (sh=50 and distance_stage1(5)='1')) then col:=C_WHITE; end if;
      else col:=C_SKY; end if;

      dxi:=to_integer(lx)-272;dyi:=to_integer(ly)-32;
      if dxi>-16 and dxi<16 and dyi>-16 and dyi<16 then
        if dyi<0 then ady:=-dyi; else ady:=dyi; end if;
        if dyi< -3 then ady2:=-(dyi+3); else ady2:=dyi+3; end if;
        disc_hw:=to_integer(CIRCLE_HW(ady));disc2_hw:=to_integer(CIRCLE_HW(ady2));
        in_disc:=dxi> -disc_hw and dxi<disc_hw;
        in_disc2:=(dxi-6)> -disc2_hw and (dxi-6)<disc2_hw;
        if in_disc and (not night or not in_disc2) then
          if night then col:=C_N_MOON; else col:=C_SUN; end if;
        end if;
      end if;

      cx:=lx+(distance_stage1 & '0');
      if cx(6 downto 5)="01" then cyy:=ly-CLOUD_Y(to_integer(cx(8 downto 7)));
        if cyy<10 then ctx:=to_integer(cx(4 downto 0));cty:=to_integer(cyy(3 downto 0));
          if (cty>=6 and ctx>=1 and ctx<=30 and not(cty=9 and (ctx<3 or ctx>28))) or
             (cty>=3 and cty<6 and ctx>=6 and ctx<=25) or
             (cty<3 and ctx>=10 and ctx<=21 and not(cty=0 and (ctx<12 or ctx>19))) then
            if night then col:=C_N_CLOUD; else col:=C_CLOUD; end if;
          end if;
        end if;
      end if;

      hx:=lx(7 downto 0)+scroll;if hx(6)='1' then tri1:=not hx(5 downto 0);else tri1:=hx(5 downto 0);end if;
      if hx(4)='1' then tri2:=not hx(3 downto 0);else tri2:=hx(3 downto 0);end if;
      hill_top:=to_unsigned(184,8)-tri1(5 downto 2)-tri2(3 downto 2);
      if ly>=hill_top and ly<GROUND_Y then if night then col:=C_N_HILL;else col:=C_HILL;end if;end if;

      gh:=wx(9 downto 4);
      if ly=GROUND_Y or (ly=GROUND_Y-1 and wx(5 downto 3)="101" and wx(7)='1') then
        if night then col:=C_N_LINE;else col:=C_LINE;end if;
      elsif ly>GROUND_Y then
        if night then col:=C_N_SAND;else col:=C_SAND;end if;
        if ly(1 downto 0)="10" and wx(2 downto 1)="00" and (gh(4 downto 0) xor ly(6 downto 2))="10110" then
          if night then col:=C_N_PEBBLE;else col:=C_PEBBLE;end if;
        end if;
      end if;

      if o_on then
        if o_bird then if night then obj_col:=C_N_BIRD;else obj_col:=C_BIRD;end if;
        elsif night then obj_col:=C_N_CACTUS;else obj_col:=C_CACTUS;end if;
        if o_eye then obj_col:=C_BLACK;end if;
      end if;
      if p_on then
        if ui_in_stage1(2)='0' then if night then player_col:=C_N_DINO;else player_col:=C_DINO;end if;
        elsif p_skin then player_col:=C_SKIN;elsif p_spot then player_col:=C_SHELL2;else player_col:=C_SHELL;end if;
      end if;

      if not alive then
        tx9:=lx-91;
        if ly(7 downto 4)="0101" and ly(3 downto 1)/="111" and tx9<144 then
          tcol:=to_integer(tx9(3 downto 1));
          if tcol<5 then glyph:=FONT_GO(to_integer(tx9(7 downto 4) & ly(3 downto 1)));
            if glyph(4-tcol)='1' then late_on:=true; end if;
          end if;
        end if;
        u:=to_integer(lx)-153;v:=to_integer(ly)-104;
        if distance_stage1>=RESTART_DELAY and distance_stage1(4)='1' and u>=0 and u<14 and v>=0 and v<16 then
          play_y2:=2*v-15;
          if play_y2>=u-15 and play_y2<=15-u then late_on:=true; end if;
        end if;
      end if;
      if ui_in_stage1(0)='1' and ly>=20 and ly<40 and ((lx>=150 and lx<156) or (lx>=164 and lx<170)) then
        late_on:=true;
      end if;
    end if;
    if night then late_col:=C_WHITE;else late_col:=C_TEXT;end if;
    if p_eye then player_eye_comb<='1';else player_eye_comb<='0';end if;
    if vis then
      if o_on then object_on_comb<='1';else object_on_comb<='0';end if;
      if p_on then player_on_comb<='1';else player_on_comb<='0';end if;
    else
      object_on_comb<='0';player_on_comb<='0';player_eye_comb<='0';
    end if;
    if late_on then late_on_comb<='1';else late_on_comb<='0';end if;
    base_rgb_comb<=col;object_rgb_comb<=obj_col;player_rgb_comb<=player_col;late_rgb_comb<=late_col;
    if ui_in_stage1(7)='0' and ui_in_stage1(0)='0' then
      if alive then if air_stage1=1 then snd<=vpos_stage1(5);elsif air_stage1=2 then snd<=vpos_stage1(4);elsif air_stage1=3 then snd<=vpos_stage1(3);
        elsif distance_stage1(7 downto 2)=0 then snd<=vpos_stage1(2);end if;
      elsif distance_stage1<8 then snd<=vpos_stage1(4);elsif distance_stage1<16 then snd<=vpos_stage1(5);elsif distance_stage1<24 then snd<=vpos_stage1(6);end if;
    end if;
  end process;

  color_select:process(base_rgb_q,object_rgb_q,player_rgb_q,late_rgb_q,
                       object_on_q,player_on_q,player_eye_q,late_on_q)
  begin
    if late_on_q='1' then rgb<=late_rgb_q;
    elsif player_eye_q='1' then rgb<=C_BLACK;
    elsif player_on_q='1' then rgb<=player_rgb_q;
    elsif object_on_q='1' then rgb<=object_rgb_q;
    else rgb<=base_rgb_q;
    end if;
  end process;

  pixel_pipeline:process(clk,rst_n)
  begin
    if rst_n='0' then
      hpos_stage1<=(others=>'0');vpos_stage1<=(others=>'0');
      distance_stage1<=(others=>'0');air_stage1<=(others=>'0');ui_in_stage1<=(others=>'0');
      hsync_stage1<='0';vsync_stage1<='0';
      base_rgb_q<=C_BLACK;object_rgb_q<=C_BLACK;player_rgb_q<=C_BLACK;late_rgb_q<=C_BLACK;
      object_on_q<='0';player_on_q<='0';player_eye_q<='0';late_on_q<='0';
      hsync_q<='0';vsync_q<='0';snd_q<='0';
      uo_out<=(others=>'0');uio_out<=(others=>'0');
    elsif rising_edge(clk) then
      hpos_stage1<=hpos;vpos_stage1<=vpos;
      distance_stage1<=distance;air_stage1<=air;ui_in_stage1<=ui_in;
      hsync_stage1<=hsync;vsync_stage1<=vsync;
      base_rgb_q<=base_rgb_comb;object_rgb_q<=object_rgb_comb;
      player_rgb_q<=player_rgb_comb;late_rgb_q<=late_rgb_comb;
      object_on_q<=object_on_comb;player_on_q<=player_on_comb;
      player_eye_q<=player_eye_comb;late_on_q<=late_on_comb;
      hsync_q<=hsync_stage1;vsync_q<=vsync_stage1;snd_q<=snd;
      uo_out<=hsync_q & rgb(0) & rgb(2) & rgb(4) & vsync_q & rgb(1) & rgb(3) & rgb(5);
      uio_out<=snd_q & "0000000";
    end if;
  end process;
  uio_oe<="10000000";
end architecture;
