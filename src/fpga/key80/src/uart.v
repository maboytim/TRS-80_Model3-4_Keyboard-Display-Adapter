`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
module uart(
   // Inputs
   clk_i,    // System clock
   uart_rx,  // UART receive wire
   wr_i,     // Strobe high to write transmit byte - sets tx_bsy_o
   rd_i,     // Strobe high to read receive byte - clears rx_rdy_o
   dat_i,    // 8-bit tx data
   // Outputs
   uart_tx,  // UART transmit wire
   tx_bsy_o, // High means UART transmit register full
   rx_rdy_o, // High means UART receive register empty
   dat_o,    // 8-bit data out
   dat_o_stb // Strobed high when dat_o changes
);

  input clk_i;
  input uart_rx;
  input wr_i;
  input rd_i;
  input [7:0] dat_i;

  output uart_tx;
  output tx_bsy_o;
  output rx_rdy_o;
  output [7:0] dat_o;
  output dat_o_stb;

  // clk_i is 27MHz.  We want a 16*115200Hz clock
  reg [25:0] d;
  reg [3:0] d16;
  wire [25:0] dInc = (~d[25]) ? (26'd16*26'd115200 - 26'd27000000) : (26'd16*26'd115200);
  wire [25:0] dNxt = d + dInc;
  always @(posedge clk_i)
  begin
    d <= dNxt;
    d16 <= d16 + { 3'b0, ~d[25] };
  end
  wire ser_clk = ~d[25]; // this is the 16*115200 Hz clock


  reg [3:0] tx_bitcount;
  reg [3:0] tx16;
  reg [8:0] tx_shifter;
  reg uart_tx_reg = 1'b1;
  reg [7:0] dat_i_reg;
  reg dat_i_reg_rdy;

  always @(posedge clk_i)
  begin
    if (ser_clk)
    begin
      if (tx_bitcount == 4'b0)
      begin
        // have a new byte
        if (dat_i_reg_rdy)
        begin
          dat_i_reg_rdy <= 1'b0;
          tx_shifter <= ~{ dat_i_reg, 1'b0 };
          tx_bitcount <= (1 + 8 + 1); // start + data + stop
          tx16 <= d16;
        end
      end
      else
      begin
        if (tx16 == d16)
        begin
          tx_shifter <= { ~1'b1, tx_shifter[8:1] };
          tx_bitcount <= tx_bitcount - 4'b1;
        end
      end
    end

    // just got a new byte
    if (wr_i)
    begin
      dat_i_reg <= dat_i;
      dat_i_reg_rdy <= 1'b1;
    end
    uart_tx_reg <= ~tx_shifter[0];
  end

  assign uart_tx = uart_tx_reg;
  assign tx_bsy_o = dat_i_reg_rdy;


  reg uart_rx_reg, uart_rx_smp;
  reg [3:0] rx_bitcount;
  reg [3:0] rx16;
  reg [8:0] rx_shifter;
  reg [7:0] dat_o_reg;
  reg dat_o_reg_rdy;
  reg dat_o_reg_stb;

  always @(posedge clk_i)
  begin
    uart_rx_reg <= uart_rx;

    if (rd_i)
    begin
      dat_o_reg_rdy <= 1'b0;
    end
    dat_o_reg_stb <= 1'b0;

    if (ser_clk)
    begin
      uart_rx_smp <= uart_rx_reg;

      if (rx_bitcount == 4'b0)
      begin
        if (uart_rx_smp & ~uart_rx_reg) // falling edge
        begin
          rx_bitcount <= 1 + 8 + 1; // start + data + stop
          rx16 <= d16; // 16x clock phase where falling edge detected
        end
      end
      else
      begin
        if ((rx16 ^ 4'b1000) == d16)
        begin
          rx_shifter <= { uart_rx_reg, rx_shifter[8:1] };

          if (rx_bitcount == 4'b1)
          begin
            dat_o_reg <= rx_shifter[8:1];
            dat_o_reg_rdy <= 1'b1;
            dat_o_reg_stb <= 1'b1;
          end

          rx_bitcount <= rx_bitcount - 4'b1;
        end
      end
    end
  end

  assign rx_rdy_o = dat_o_reg_rdy;
  assign dat_o = dat_o_reg;
  assign dat_o_stb = dat_o_reg_stb;

endmodule
