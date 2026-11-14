`timescale 1ns/1ps

module cam_init 
#(
    parameter CLK_IN_KHZ = 100_000, //100 MHz
    parameter SCL_CLK_FREQ_KHZ = 200 //200 khz
)
(
    input clk,
    input arstn,
    input i_config_start,

    output o_scl,
    output o_config_done,
    inout io_sda

);

wire [7:0] rom_addr;
wire [15:0] rom_data;
wire sccb_busy;
wire sccb_done;
wire sccb_start;
wire [7:0] sccb_sub_addr;
wire [7:0] sccb_data;
wire [1:0] sccb_mode;
wire [7:0] sccb_rd_data; //not neccessory


ov7670_rom rom_mem 
(
    .clk(clk),
    .arstn(arstn),
    .i_addr(rom_addr),
    .o_dout(rom_data)    
);

cam_config 
#(
    .CLK_IN_KHZ(CLK_IN_KHZ)
)
OV7670_config
(
    .clk(clk),
    .arstn(arstn),
    .i_config_start(i_config_start),
    .i_sccb_ready(~sccb_busy),
    .i_sccb_done(sccb_done),
    .i_rom_data(rom_data),
    .o_rom_addr(rom_addr),
    .o_sccb_start(sccb_start),
    .o_sccb_sub_addr(sccb_sub_addr),
    .o_sccb_mode(sccb_mode),
    .o_sccb_data(sccb_data),
    .o_config_done(o_config_done)
);

sccb_master
#(
    .CLK_FREQ_KHZ(CLK_IN_KHZ),
    .SCL_CLK_FREQ_KHZ(SCL_CLK_FREQ_KHZ)
)
dut_sccb_master
(
    .clk(clk), 
    .arstn(arstn), 
    .i_start(sccb_start),
    .i_sda(io_sda),
    .i_sub_addr(sccb_sub_addr),
    .i_wdata(sccb_data),
    .i_mode(sccb_mode), 
    .o_rdata(sccb_rd_data),
    .o_scl(o_scl),
    .o_sda_release(io_sda), 
    .o_done(sccb_done),
    .o_busy(sccb_busy)

);
endmodule