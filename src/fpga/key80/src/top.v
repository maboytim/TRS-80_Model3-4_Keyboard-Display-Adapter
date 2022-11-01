`timescale 1ns / 1ps

module top(
   input clk_in,
   input [1:0] sw,
   output [5:0] led,
   output uart_tx,
   input uart_rx,
   input vsync_in,
   input hsync_in,
   input pixel_in,

   input [7:0] ad,

   output rst,
   output [7:0] da,
   output den_n,

   input ps2_dta,
   input ps2_clk,

   input test_in,

   // HDMI
   output [2:0] tmds_p,
   output [2:0] tmds_n,
   output tmds_clock_p,
   output tmds_clock_n
);

//-----PS/2------------------------------------------------------------------------

reg [1:0] ps2_clk_dly;
reg [1:0] ps2_dta_dly;

always @ ( posedge clk_in )
begin
   ps2_clk_dly <= { ps2_clk_dly[0], (^ps2_clk_dly) ? ps2_clk_dly[0] : ~ps2_clk }; // glitch suppression
   ps2_dta_dly <= { ps2_dta_dly[0], ~ps2_dta }; // no glitch suppression
end


reg [9:0] ps2_dta_shr;
reg [7:0] ps2_dta_hld;
reg ps2_dta_hld_rdy;

always @ ( posedge clk_in )
begin
   if(ps2_clk_dly == ~2'b10) // falling edge
   begin
      if(ps2_dta_shr[9] == ~1'b0)
      begin
         if(ps2_dta_dly[1] == ~1'b1)
         begin
            ps2_dta_hld <= ~{ ps2_dta_shr[1], ps2_dta_shr[2], ps2_dta_shr[3], ps2_dta_shr[4],
                              ps2_dta_shr[5], ps2_dta_shr[6], ps2_dta_shr[7], ps2_dta_shr[8] };
            ps2_dta_hld_rdy <= 1'b1;
         end
         else
         begin
            ps2_dta_hld_rdy <= 1'b0;
         end
         ps2_dta_shr <= 10'b0;
      end
      else
      begin
         ps2_dta_shr <= { ps2_dta_shr[8:0], ps2_dta_dly[1] };
         ps2_dta_hld_rdy <= 1'b0;
      end
   end
   else
   begin
      ps2_dta_hld_rdy <= 1'b0;
   end
end


reg [7:0] ps2_dta_reg, prev_ps2_dta_reg;
reg ps2_release, ps2_ext;
reg ps2_dta_reg_rdy;

always @ ( posedge clk_in )
begin
   if(ps2_dta_hld_rdy)
   begin
      ps2_dta_reg <= ps2_dta_hld;
      prev_ps2_dta_reg <= ps2_dta_reg;

      if(ps2_dta_hld == 8'hf0 || ps2_dta_hld == 8'he0)
         ps2_dta_reg_rdy <= 1'b0;
      else
      begin
         ps2_release <= (ps2_dta_reg == 8'hf0);
         ps2_ext <= (ps2_dta_reg == 8'hf0) ? (prev_ps2_dta_reg == 8'he0) : (ps2_dta_reg == 8'he0);
         ps2_dta_reg_rdy <= 1'b1;
      end
   end
   else
      ps2_dta_reg_rdy <= 1'b0;
end


// Map ps2 scan codes to switch closures in the trs-90 keyboard matrix.
// Where the ps2 and trs-80 keyboards agree the mapping is easy but where they
// differ creates several special cases.  For example the 1! key is the same
// for both keyboards so it maps simply to a single matrix position.  However
// for example the 8( key maps to different matrix positions depending on
// whether it is un-shifted 8 or shifted (.  Additionally the SHIFT key is
// sometimes required for the ps2 key but not expected for the trs-80 key and
// vice versa so the SHIFT key has to manipulated and can't be just directly
// connected to the SHIFT positions in the trs-80 matrix.
// See https://forum.digikey.com/t/ps-2-keyboard-interface-vhdl/12614 for the
// ps2 scan codes.

// These are the trs-80 keyboard matrix.  The ps2 closures are mapped to the
// corresponding closures in tis matrix.
reg [7:0] kbd0, kbd1, kbd2;
reg [2:0] kbd3;
reg [7:0] kbd4, kbd5, kbd6;
reg [1:0] kbd7;


// These are the ps2 key closures.  There is a direct one to one correspondence
// with the keys.
reg [25:0] ps2_a_z; // keys a-z
reg [9:0] ps2_0_9; // keys 0-9
reg ps2_semi, ps2_tick, ps2_comma, ps2_dot, ps2_slash;
reg ps2_esc, ps2_bktick, ps2_minus, ps2_equ, ps2_tab, ps2_bkspc, ps2_enter, ps2_space;
reg ps2_home, ps2_end,ps2_caps;
reg ps2_lbrkt, ps2_rbrkt, ps2_bkslsh;
reg ps2_up, ps2_down, ps2_left, ps2_right;
reg [9:0] ps2_kp0_9;
reg ps2_kpstar, ps2_kpplus, ps2_kpminus, ps2_kpdot, ps2_kpslash, ps2_kpenter;
reg [1:0] ps2_shft, ps2_ctrl, ps2_alt;
reg ps2_del;
reg ps2_f9, ps2_f10, ps2_f11, ps2_f12;

// These are overrides for the SHIFT key.  Shift_on forces the SHIFT key to be
// pressed when it is actually released, and shift_off forces the SHIFT key to
// be released when it is actually pressed.
wire [1:0] shift_on  = { (ps2_bktick & ~|ps2_shft)
                       | (ps2_tick   & ~|ps2_shft)
                       |  ps2_kpstar
                       |  ps2_kpplus
                       | (ps2_equ    & ~|ps2_shft),
                         (ps2_bktick & ~|ps2_shft)
                       | (ps2_tick   & ~|ps2_shft)
                       |  ps2_kpstar
                       |  ps2_kpplus
                       | (ps2_equ    & ~|ps2_shft)
                       |  ps2_caps 
                       |  |ps2_ctrl };
wire [1:0] shift_off = { (ps2_0_9[2] & |ps2_shft)
                       | (ps2_0_9[6] & |ps2_shft)
                       | (ps2_semi   & |ps2_shft)
                       |  ps2_kpminus
                       |  ps2_kpdot
                       |  ps2_kpslash
                       | (|ps2_kp0_9 & |ps2_shft), // all shift-kp#
                         (ps2_0_9[2] & |ps2_shft)
                       | (ps2_0_9[6] & |ps2_shft)
                       | (ps2_semi   & |ps2_shft)
                       |  ps2_kpminus
                       |  ps2_kpdot
                       |  ps2_kpslash
                       | (|ps2_kp0_9 & |ps2_shft) }; // all shift-kp#

always @ (posedge clk_in)
begin
   // convert each key press/release to a switch close/open
   if(ps2_dta_reg_rdy)
   begin
      case({ ps2_ext, ps2_dta_reg })
         9'h01c: ps2_a_z[ 0] <= ~ps2_release; // A
         9'h032: ps2_a_z[ 1] <= ~ps2_release; // B
         9'h021: ps2_a_z[ 2] <= ~ps2_release; // C
         9'h023: ps2_a_z[ 3] <= ~ps2_release; // D
         9'h024: ps2_a_z[ 4] <= ~ps2_release; // E
         9'h02b: ps2_a_z[ 5] <= ~ps2_release; // F
         9'h034: ps2_a_z[ 6] <= ~ps2_release; // G
         9'h033: ps2_a_z[ 7] <= ~ps2_release; // H
         9'h043: ps2_a_z[ 8] <= ~ps2_release; // I
         9'h03b: ps2_a_z[ 9] <= ~ps2_release; // J
         9'h042: ps2_a_z[10] <= ~ps2_release; // K
         9'h04b: ps2_a_z[11] <= ~ps2_release; // L
         9'h03a: ps2_a_z[12] <= ~ps2_release; // M
         9'h031: ps2_a_z[13] <= ~ps2_release; // N
         9'h044: ps2_a_z[14] <= ~ps2_release; // O
         9'h04d: ps2_a_z[15] <= ~ps2_release; // P
         9'h015: ps2_a_z[16] <= ~ps2_release; // Q
         9'h02d: ps2_a_z[17] <= ~ps2_release; // R
         9'h01b: ps2_a_z[18] <= ~ps2_release; // S
         9'h02c: ps2_a_z[19] <= ~ps2_release; // T
         9'h03c: ps2_a_z[20] <= ~ps2_release; // U
         9'h02a: ps2_a_z[21] <= ~ps2_release; // V
         9'h01d: ps2_a_z[22] <= ~ps2_release; // W
         9'h022: ps2_a_z[23] <= ~ps2_release; // X
         9'h035: ps2_a_z[24] <= ~ps2_release; // Y
         9'h01a: ps2_a_z[25] <= ~ps2_release; // Z

         9'h016: ps2_0_9[ 1] <= ~ps2_release; // 1 !
         9'h01e: ps2_0_9[ 2] <= ~ps2_release; // 2 @ 
         9'h026: ps2_0_9[ 3] <= ~ps2_release; // 3 #
         9'h025: ps2_0_9[ 4] <= ~ps2_release; // 4 $
         9'h02e: ps2_0_9[ 5] <= ~ps2_release; // 5 %
         9'h036: ps2_0_9[ 6] <= ~ps2_release; // 6 ^
         9'h03d: ps2_0_9[ 7] <= ~ps2_release; // 7 &
         9'h03e: ps2_0_9[ 8] <= ~ps2_release; // 8 *
         9'h046: ps2_0_9[ 9] <= ~ps2_release; // 9 (
         9'h045: ps2_0_9[ 0] <= ~ps2_release; // 0 )

         9'h04c: ps2_semi    <= ~ps2_release; // ; :
         9'h052: ps2_tick    <= ~ps2_release; // ' "
         9'h041: ps2_comma   <= ~ps2_release; // , <
         9'h049: ps2_dot     <= ~ps2_release; // . >
         9'h04a: ps2_slash   <= ~ps2_release; // / ?

         9'h076: ps2_esc     <= ~ps2_release; // ESC
         9'h00e: ps2_bktick  <= ~ps2_release; // ` ~
         9'h04e: ps2_minus   <= ~ps2_release; // - _
         9'h055: ps2_equ     <= ~ps2_release; // = +
         9'h00d: ps2_tab     <= ~ps2_release; // TAB
         9'h066: ps2_bkspc   <= ~ps2_release; // BACKSPACE
         9'h05a: ps2_enter   <= ~ps2_release; // ENTER
         9'h029: ps2_space   <= ~ps2_release; // SPACE

         9'h16c: ps2_home    <= ~ps2_release; // HOME
         9'h169: ps2_end     <= ~ps2_release; // END
         9'h058: ps2_caps    <= ~ps2_release; // CAPS

         9'h054: ps2_lbrkt   <= ~ps2_release; // [ {
         9'h05b: ps2_rbrkt   <= ~ps2_release; // ] }
         9'h05d: ps2_bkslsh  <= ~ps2_release; // \ |

         9'h175: ps2_up      <= ~ps2_release; // UP ARROW
         9'h172: ps2_down    <= ~ps2_release; // DOWN ARROW
         9'h16b: ps2_left    <= ~ps2_release; // LEFT ARROW
         9'h174: ps2_right   <= ~ps2_release; // RIGHT ARROW

         9'h070: ps2_kp0_9[0]<= ~ps2_release; // kp 0
         9'h069: ps2_kp0_9[1]<= ~ps2_release; // kp 1
         9'h072: ps2_kp0_9[2]<= ~ps2_release; // kp 2
         9'h07a: ps2_kp0_9[3]<= ~ps2_release; // kp 3
         9'h06b: ps2_kp0_9[4]<= ~ps2_release; // kp 4
         9'h073: ps2_kp0_9[5]<= ~ps2_release; // kp 5
         9'h074: ps2_kp0_9[6]<= ~ps2_release; // kp 6
         9'h06c: ps2_kp0_9[7]<= ~ps2_release; // kp 7
         9'h075: ps2_kp0_9[8]<= ~ps2_release; // kp 8
         9'h07d: ps2_kp0_9[9]<= ~ps2_release; // kp 9
         9'h07c: ps2_kpstar  <= ~ps2_release; // kp *
         9'h079: ps2_kpplus  <= ~ps2_release; // kp +
         9'h07b: ps2_kpminus <= ~ps2_release; // kp -
         9'h071: ps2_kpdot   <= ~ps2_release; // kp .
         9'h14a: ps2_kpslash <= ~ps2_release; // kp /
         9'h15a: ps2_kpenter <= ~ps2_release; // kp ENTER

         9'h012: ps2_shft[0] <= ~ps2_release; // LEFT SHIFT
         9'h059: ps2_shft[1] <= ~ps2_release; // RIGHT SHIFT
         9'h014: ps2_ctrl[0] <= ~ps2_release; // LEFT CTL
         9'h114: ps2_ctrl[1] <= ~ps2_release; // RIGHT CTL
         9'h011: ps2_alt[0]  <= ~ps2_release; // LEFT ALT
         9'h111: ps2_alt[1]  <= ~ps2_release; // RIGHT ALT
         9'h171: ps2_del     <= ~ps2_release; // DELETE

         9'h001: ps2_f9      <= ~ps2_release; // F9
         9'h009: ps2_f10     <= ~ps2_release; // F10
         9'h078: ps2_f11     <= ~ps2_release; // F11
         9'h007: ps2_f12     <= ~ps2_release; // F12
      endcase
   end

   // map the switch closures to the trs-80 keyboard matrix

   // @
   kbd0[0] <= (ps2_0_9[2]   &  |ps2_shft) // @ (shift-2) include in shift_off
            | (ps2_bktick   & ~|ps2_shft);// `           include in shift_on
   // A-G
   kbd0[7:1] <= ps2_a_z[6:0];

   // H-O
   kbd1    <= ps2_a_z[14:7];
   // P-W
   kbd2    <= ps2_a_z[22:15];
   // X-Z
   kbd3    <= ps2_a_z[25:23];
      
   // 0
   kbd4[0] <= (ps2_0_9[0]   & ~|ps2_shft)  // 0
            | (ps2_kp0_9[0] & ~|ps2_shft)  // kp0
            |  ps2_caps;                   // CAPS        include in shift_on[0]
   // 1 !
   kbd4[1] <=  ps2_0_9[1]                  // 1 !
            | (ps2_kp0_9[1] & ~|ps2_shft); // kp1
   // 2 "
   kbd4[2] <= (ps2_0_9[2]   & ~|ps2_shft)  // 2
            | (ps2_kp0_9[2] & ~|ps2_shft)  // kp2
            | (ps2_tick     &  |ps2_shft); //   "
   // 3 #
   kbd4[3] <=  ps2_0_9[3]                  // 3 #
            | (ps2_kp0_9[3] & ~|ps2_shft); // kp3
   // 4 $
   kbd4[4] <=  ps2_0_9[4]                  // 4 $
            | (ps2_kp0_9[4] & ~|ps2_shft); // kp4
   // 5 %
   kbd4[5] <=  ps2_0_9[5]                  // 5 %
            | (ps2_kp0_9[5] & ~|ps2_shft); // kp5
   // 6 &
   kbd4[6] <= (ps2_0_9[6]   & ~|ps2_shft)  // 6
            | (ps2_kp0_9[6] & ~|ps2_shft)  // kp6
            | (ps2_0_9[7]   &  |ps2_shft); //   &
   // 7 '
   kbd4[7] <= (ps2_0_9[7]   & ~|ps2_shft)  // 7
            | (ps2_kp0_9[7] & ~|ps2_shft)  // kp7
            | (ps2_tick     & ~|ps2_shft); // '           include in shift_on

   // 8 (
   kbd5[0] <= (ps2_0_9[8]   & ~|ps2_shft)  // 8
            | (ps2_kp0_9[8] & ~|ps2_shft)  // kp8
            | (ps2_0_9[9]   &  |ps2_shft); //   (
   // 9 )
   kbd5[1] <= (ps2_0_9[9]   & ~|ps2_shft)  // 9
            | (ps2_kp0_9[9] & ~|ps2_shft)  // kp9
            | (ps2_0_9[0]   &  |ps2_shft); //   )
   // : *
   kbd5[2] <= (ps2_semi     &  |ps2_shft)  //   :         include in shift_off
            |  ps2_kpstar                  // kp*         include in shift_on
            | (ps2_0_9[8]   &  |ps2_shft); //   *
   // ; +
   kbd5[3] <= (ps2_semi     & ~|ps2_shft)  // ;
            |  ps2_kpplus                  // kp+         include in shift_on
            | (ps2_equ      &  |ps2_shft); //   +
   // , <
   kbd5[4] <=  ps2_comma;                  // , <
   // - =
   kbd5[5] <= (ps2_minus    & ~|ps2_shft)  // -
            |  ps2_kpminus                 // kp-         include in shift_off
            | (ps2_equ      & ~|ps2_shft); // =           include in shift_on
   // . >
   kbd5[6] <=  ps2_dot                     // . >
            |  ps2_kpdot;                  // kp.         include in shift_off
   // / ?
   kbd5[7] <=  ps2_slash                   // / ?
            |  ps2_kpslash;                // kp/         include in shift_off

   // ENTER
   kbd6[0] <=  ps2_enter                   // ENTER
            |  ps2_kpenter;                // kpenter
   // CLEAR
   kbd6[1] <=  ps2_home                    // HOME
            | (ps2_kp0_9[7] &  |ps2_shft)  // shift-kp7   include in shift_off
            |  ps2_bkslsh;                 // \ |
   // BREAK
   kbd6[2] <=  ps2_esc                     // ESC
            | (ps2_kp0_9[1] &  |ps2_shft)  // shift-kp1   include in shift_off
            |  ps2_end;                    // END
   // UP ARROW
   kbd6[3] <=  ps2_up                      // UP ARROW
            | (ps2_kp0_9[8] &  |ps2_shft)  // shift-kp8   include in shift_off
            | (ps2_0_9[6]   &  |ps2_shft); //   ^         include in shift_off
   // DOWN ARROW
   kbd6[4] <=  ps2_down                    // DOWN ARROW
            | (ps2_kp0_9[2] &  |ps2_shft)  // shift-kp2   include in shift_off
            |  |ps2_ctrl;                  // L/R CTRL    nclude in shift_on[0]
   // LEFT ARROW
   kbd6[5] <=  ps2_left                    // LEFT ARROW
            | (ps2_kp0_9[4] &  |ps2_shft)  // shift-kp4   include in shift_off
            |  ps2_bkspc;                  // BACKSPACE
   // TAB / RIGHT ARROW
   kbd6[6] <=  ps2_tab                     // TAB
            |  ps2_right                   // RIGHT ARROW
            | (ps2_kp0_9[6] &  |ps2_shft); // shift-kp6   include in shift_off
   // SPACE
   kbd6[7] <=  ps2_space;                  // SPACE

   // LEFT SHIFT
   kbd7[0] <=  ps2_shft[0];                // LEFT SHIFT
   // RIGHT SHIFT
   kbd7[1] <=  ps2_shft[1];                // RIGHT SHIFT
end

// Output the selected row of the keyboard matrix.
assign da = ~( ({8{~ad[0]}} & kbd0) |
               ({8{~ad[1]}} & kbd1) |
               ({8{~ad[2]}} & kbd2) |
               ({8{~ad[3]}} & {5'b00000, kbd3}) |
               ({8{~ad[4]}} & kbd4) |
               ({8{~ad[5]}} & kbd5) |
               ({8{~ad[6]}} & kbd6) |
               ({8{~ad[7]}} & {6'b000000, kbd7 & ~shift_off | shift_on}) );
assign den_n = ~|da;

// map ctrl-ald-del to reset
assign rst = ~sw[0] | ((|ps2_ctrl) & (|ps2_alt) & (ps2_del | ps2_kpdot));

assign led[2:0] = ~{ |shift_off | rst, |shift_on | rst, |ps2_shft | rst };

//---------------------------------------------------------------------------------

// Output the ps2 scan codes as ascii hex to the uart.  Each scan code resuts
// in two ascii characters.  Assume the uart baud (115200 in this case) is more
// than 2x the ps2 clock so there is time to output two bytes per scancode
// (otherwise characters will just be dropped).  When a scan code is generated
// the high nibble is (converted to ascii hex and) sent directly to the uart and
// the low nibble is buffered until the uart is ready for the next character.

wire uart_tx_bsy;

reg [3:0] ps2_lo_nbl;
reg ps2_lo_nbl_bsy;

always @ (posedge clk_in)
begin
   if(ps2_dta_hld_rdy)
   begin
      ps2_lo_nbl <= ps2_dta_hld[3:0];
      ps2_lo_nbl_bsy <= 1'b1;
   end
   else if(ps2_lo_nbl_bsy & ~uart_tx_bsy)
      ps2_lo_nbl_bsy <= 1'b0;
end


wire [3:0] uart_tx_nbl = ps2_dta_hld_rdy ? ps2_dta_hld[7:4] : ps2_lo_nbl;
wire [7:0] uart_tx_byt = 8'h30 + {4'h0, uart_tx_nbl} + (uart_tx_nbl < 4'd10 ? 8'h00 : 8'h07);
wire uart_rx_byt_rdy = ps2_dta_hld_rdy ? 1'b1 : (ps2_lo_nbl_bsy & ~uart_tx_bsy);

uart uart(
   // Inputs
   .clk_i(clk_in),             // System clock
   .uart_rx(uart_rx),          // UART receive wire
   .wr_i(uart_rx_byt_rdy),     // Strobe high to write transmit byte - sets tx_bsy_o
   .rd_i(1'b0),                // Strobe high to read receive byte - clears rx_rdy_o
   .dat_i(uart_tx_byt),        // 8-bit tx data
   // Outputs
   .uart_tx(uart_tx),          // UART transmit wire
   .tx_bsy_o(uart_tx_bsy),     // High means UART transmit register full
   .rx_rdy_o(),                // High means UART receive register empty
   .dat_o(),                   // 8-bit data out
   .dat_o_stb()                // Strobed high when dat_o changes
);

//---------------------------------------------------------------------------------

// 126MHz clock
wire vgaclk_x5;

Gowin_rPLL0 vgaclkpll(
   .clkout(vgaclk_x5), //output clkout
   .clkin(clk_in)     //input clkin
);

// 25.2MHz clock
wire vgaclk;

Gowin_CLKDIV clkdiv(
  .clkout(vgaclk),    //output clkout
  .hclkin(vgaclk_x5), //input hclkin
  .resetn(1'b1)       //input resetn
);

//-----HDMI------------------------------------------------------------------------

logic vga_rgb;

//pll pll(.c0(clk_pixel_x5), .c1(clk_pixel), .c2(clk_audio));

logic [15:0] audio_sample_word [1:0] = '{16'd0, 16'd0};

logic [23:0] rgb = 24'd0;
logic [23:0] rgb_screen_color = 24'hffffff;  // White
//logic [23:0] rgb_screen_color = 24'h33ff33;  // Green - from trs-io {51, 255, 51}
//logic [23:0] rgb_screen_color = 24'hffb100;  // Amber - from trs-io {255, 177, 0}}
logic [9:0] cx, frame_width, screen_width;
logic [9:0] cy, frame_height, screen_height;

always @(posedge clk_in)
begin
   if(ps2_f10) rgb_screen_color <= 24'hffffff;  // White
   else if(ps2_f11) rgb_screen_color <= 24'h33ff33;  // Green - from trs-io {51, 255, 51}
   else if(ps2_f12) rgb_screen_color <= 24'hffb100;  // Amber - from trs-io {255, 177, 0}}
end

always @(posedge vgaclk)
begin
  if(!sw[1] && (cx == 0 || cx == (screen_width - 1) || cy == 0 || cy == (screen_height - 1)))
     rgb <= 24'h0000ff;
  else
  if(cx >= 64 && cx < 576 && cy >= 48 && cy < 432)
     rgb <= vga_rgb ? rgb_screen_color : 24'b0;
  else
     rgb <= test_in ? 24'h404040 : 24'h000000;
end

wire [2:0] tmds_x;
wire tmds_clock_x;

// 640x480 @ 60Hz
hdmi #(.VIDEO_ID_CODE(1), .VIDEO_REFRESH_RATE(60), .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16)) hdmi(
  .clk_pixel_x5(vgaclk_x5),
  .clk_pixel(vgaclk),
  .clk_audio(1'b0),
  .reset(1'b0),
  .rgb(rgb),
  .audio_sample_word(audio_sample_word),
  .tmds(tmds_x),
  .tmds_clock(tmds_clock_x),
  .cx(cx),
  .cy(cy),
  .frame_width(frame_width),
  .frame_height(frame_height),
  .screen_width(screen_width),
  .screen_height(screen_height)
);

ELVDS_OBUF tmds [2:0] (
  .O(tmds_p),
  .OB(tmds_n),
  .I(tmds_x)
);

ELVDS_OBUF tmds_clock(
  .O(tmds_clock_p),
  .OB(tmds_clock_n),
  .I(tmds_clock_x)
);

//-----DPLL------------------------------------------------------------------------

reg [1:0] hsync_in_dly;

always @ (posedge vgaclk_x5)
begin
   hsync_in_dly <= { hsync_in_dly[0], hsync_in }; // no glitch suppression
   //hsync_in_dly <= { hsync_in_dly[0], (^hsync_in_dly) ? hsync_in_dly[0] : hsync_in }; // glitch suppression
end


// The M3 has 640=80*8 pixels per line, 512=64*8 active and 128 blanked.
// The horizontal rate is 15.84kHz.  The dotclock is 640*15.84=10.1376MHz
reg [31:0] nco;
reg [4:0] prev_nco;
reg [9:0] hcnt; // mod 640 horizontal counter -320..319
reg [9:0] phserr; // phaase error
reg [4:0] phserr_rdy; // strobe to update loop filter
reg [15:0] nco_in; // frequency control input
reg [8:0] lock;

always @ (posedge vgaclk_x5)
begin
   // 0x0A4C6B6F = 2^31*10.1376/126
   nco <= {1'b0, nco[30:0]} + {1'b0, 31'h0A4C6B6F + {{10{nco_in[15]}}, nco_in, 5'b0}};
   // The nco is the fractional part of hcnt.  However the carry-out from the nco is
   // pipelined (delayed one clock) so it is actually the delayed nco that is the
   // fractional part.
   prev_nco <= nco[30:26];

   // When locked the hsync will sample hcnt when it crosses through zero.
   // The hsync signal is generated by a one-shot so only one edge is reliabe
   // which from observation is the rising edge.
   if(hsync_in_dly == 2'b01) // rising edge
   begin
      // If the hsync is in the neighborhood of zero crossing then take the offset
      // as the phase error.  Otherwise just reset hcnt to align it to hsync.
      if(hcnt[9:4] == 6'b111111 || hcnt[9:4] == 6'b000000)
      begin
         //phserr <= sw[0] ? -{hcnt[4:0], prev_nco} : 10'd0;
         phserr <= -{hcnt[4:0], prev_nco};
         phserr_rdy <= 1'b1;
         if(nco[31])
            hcnt <= (hcnt == 10'd319) ? -10'd320 : (hcnt + 10'd1);
         lock <= lock + {8'b0, ~lock[8]};
      end
      else
      begin
         phserr_rdy <= 1'b0;
         hcnt <= 10'd0;
         lock <= 9'b0;
      end
   end
   else
   begin
      phserr_rdy <= 1'b0;
      if(nco[31])
         hcnt <= (hcnt == 10'd319) ? -10'd320 : (hcnt + 10'd1);
   end
end

assign led[5] = ~lock[8];


// Simple PI controller.
// The integral path gain is 1/8 the proportional path gain.
// The loop gain is determined by position where the loop filter
// output is added in to the nco.  The nco pull range is determined
// by this gain and the number of bits in the error integrator.
// The values used here were determined emperically.
reg [15:0] phserr_int; // phase error integrator

always @ (posedge vgaclk_x5)
begin
   // Update the integrator when the phase error is updated.
   if(phserr_rdy)
   begin
      //    siiiiii.iiiiiiiii  phserr_int
      //  + SSSSSSs.eeeeeeeee  {{6{phserr[9]}}, phserr}
      phserr_int <= phserr_int + {{6{phserr[9]}}, phserr};
   end
   //   siiiiii.iiiiiiiii  phserr_int
   // + SSSs.eeeeeeeee000  {{3{phserr[9]}}, phserr, 3'b000}
   nco_in <= phserr_int + {{3{phserr[9]}}, phserr, 3'b000};
end


//assign gpio_29 = hcnt[9];
//assign gpio_30 = nco[30];

//========================================================================

// 10.1376MHz dot clock
wire dotclk;

BUFG dotclk_bufg(
   .O(dotclk),
   .I(~nco[30])
);


// Synchronize the hzync, vsync, and pixel signals to the recovered dotclk.
// From observation hsync rises on the dotclk rising edge so sample with
// falling.
// so sample them with the dotclk rising edge.

reg [1:0] hsync_in_shr;

always @ (negedge dotclk)
begin
   hsync_in_shr <= {hsync_in_shr[0], hsync_in};
end


// The vsync signal is generated by a one-shot so only one edge is reliabe
// which from observation is the falling edge - and which from observation
// falls on the dotclk falling edge so sample it with the dotclk rising edge.

reg [1:0] vsync_in_shr;

always @ (posedge dotclk)
begin
   vsync_in_shr <= {vsync_in_shr[0], vsync_in};
end


reg [7:0] pixel_in_shr;

always @ (negedge dotclk)
begin
   pixel_in_shr <= {pixel_in_shr[6:0], pixel_in};
end

//=================================================================================

// The horizontal and vertical oscillators (looping counters).
// These don't have to be oscillators - they could just be one-shots that trigger
// from their respective syncs.
// The blanking periods correspond to when the counters are negative.

reg [9:0] hcnt_in; // -16*8..64*8-1
// The M3 has 264=22*12 lines @60Hz and 312=26*12 lines @50Hz, 192=16*12 active
// and the rest blanked. 
reg [8:0] vcnt_in; // 60Hz: -6*12..16*12-1 (50Hz: -10*12..16*12-1)
reg pix_wr;
reg hcheck, vcheck;

always @ (posedge dotclk)
begin
   // The horizontal sync value -102 was found experimentally such that the
   // active portion of the line is captured.  This can be tweaked +/- to shift
   // the captured portion left/right.
   if(hsync_in_shr == 2'b01) // rising edge
   begin
      hcnt_in <= -10'd102;
      // If the counter modulo is right then once synced the counter will already
      // be transitioning to the sync count when the horizontal sync occurs.
      hcheck <= (hcnt_in == -10'd103);
   end
   else
   begin
      hcnt_in <= (hcnt_in == 10'd511) ? -10'd128 : (hcnt_in + 10'd1);
   end

   // The vertical sync value -36 was found experimentally such that the
   // active portion of the display is captured.
   if(vsync_in_shr == 2'b10) // falling edge
   begin
      vcnt_in <= -9'd36;
      // If the counter modulo is right then once synced the counter will already
      // be at the sync count when the vertical sync occurs.
      vcheck <= (vcnt_in == -9'd36);
   end
   else
   begin
      if(hcnt_in == 10'd511)
         vcnt_in <= (vcnt_in == 9'd191) ? -9'd72 : (vcnt_in + 9'd1);
   end

   // The pix_wr write pulse is generated only during the active portion of the display
   // because the address to the ram isn't valid during the inactive portion.
   // Any hcnt_in[2:0] can be used here, the hsync sync value can just be adjusted.
   // A value of 3'b110 is used here so that the high part of hcnt_in doesn't
   // increment on the same clock.
   pix_wr <= (hcnt_in[9] == 1'b0 && hcnt_in[2:0] == 3'b110 && vcnt_in[8] == 1'b0);
end

assign led[4:3] = {~vcheck, ~hcheck};

//=================================================================================

wire [9:0] cxx = cx - (10'd64 - 10'd8);
wire [9:0] cyy = cy - 10'd48;
wire [7:0] vgadta;

Gowin_DPB display_ram(
   .clka(dotclk),              //input clka
   .cea(pix_wr),               //input cea
   .ada({vcnt_in[7:0], hcnt_in[8:3]}), //input [13:0] ada
   .douta(),                   //output [7:0] douta
   .dina(pixel_in_shr),        //input [7:0] dina
   .ocea(1'b0),                //input ocea
   .wrea(pix_wr),              //input wrea
   .reseta(1'b0),              //input reseta

   .clkb(vgaclk),              //input clkb
   .ceb(cxx[2:0] == 3'b101),   //input ceb
   .adb({cyy[8:1], cxx[8:3]}), //input [13:0] adb
   .doutb(vgadta),             //output [7:0] doutb
   .dinb(8'b0),                //input [7:0] dinb
   .oceb(cxx[2:0] == 3'b110),  //input oceb
   .wreb(1'b0),                //input wreb
   .resetb(1'b0)               //input resetb
);


reg [7:0] vgashr;

always @ (posedge vgaclk)
begin
   vgashr <= (cxx[2:0] == 3'b111) ? vgadta : {vgashr[6:0], 1'b0};
end

// This is one vgaclk earlier than the hdmi wants the rgb data.
// This is to allow for the rgb register that was in the original hdmi example.
assign vga_rgb = vgashr[7];

endmodule
