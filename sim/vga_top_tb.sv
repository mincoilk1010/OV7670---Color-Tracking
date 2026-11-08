`timescale 1ns / 1ps

module vga_top_tb (
);
    logic clk;
    logic arstn = 1'b1;
    wire hsync, vsync;
    wire [3:0] red, green, blue;

    vga_top DUT (
        .clk(clk),
        .arstn(arstn),
        .hsync(hsync),
        .vsync(vsync),
        .red(red),
        .green(green),
        .blue(blue)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("vga_test.vcd");
        $dumpvars(0, vga_top_tb);
        #1 arstn = 1'b0;
        #200 arstn = 1'b1;
        #20_000_000 $finish;
    end
endmodule