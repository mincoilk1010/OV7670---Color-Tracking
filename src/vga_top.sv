module vga_top (
    input clk,
    input arstn,
    output hsync,
    output vsync,
    output [3:0] red,
    output [3:0] green,
    output [3:0] blue
);
    wire clk_25Mhz;
    wire active;
    wire [9:0] h_count, v_count;

    clk_div  
    #(
        .FREQ_IN(100),
        .FREQ_OUT(25)
    )
    clock_divider 
    (
        .clk_in(clk),
        .arstn(arstn),
        .clk_out(clk_25Mhz)
    );

    vga_timing timing (
        .clk(clk_25Mhz),
        .arstn(arstn),
        .hsync(hsync),
        .vsync(vsync),
        .h_count(h_count),
        .v_count(v_count),
        .active(active)
    );

    assign red = (active) ? 4'hF : 4'h0;
    assign green = (active) ? 4'hF : 4'h0;
    assign blue = (active) ? 4'hF : 4'h0;
endmodule