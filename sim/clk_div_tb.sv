`timescale 1ns/1ps

module clk_div_tb ();

    logic clk_in = 1'b0;
    logic arstn = 1'b1;
    wire clk_out;

    clk_div dut_clk_div (
        .clk_in(clk_in),
        .arstn(arstn),
        .clk_out(clk_out)
    );

    initial begin
        forever begin
            #5 clk_in = ~clk_in;
        end
    end

    initial begin
        $dumpfile("clk_div_test.vcd");
        $dumpvars(0, clk_div_tb);
        arstn = 1'b1;
        #1;
        arstn = 1'b0;
        #9;
        arstn = 1'b1;
        #1000 $finish;
    end
endmodule