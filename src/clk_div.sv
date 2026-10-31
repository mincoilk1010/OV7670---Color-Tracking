module clk_div 
#(
    parameter FREQ_IN = 100, //MHz 
    parameter FREQ_OUT = 25, //Mhz
    parameter CNT_MAX = (FREQ_IN/(2*FREQ_OUT)) - 1
)
(
    input logic clk_in,
    input logic arstn, 
    output logic clk_out 
);
    logic [$clog2(CNT_MAX + 1) - 1 : 0] cnt;

    always_ff @(posedge clk_in or negedge arstn) begin
        if(~arstn) begin
            clk_out <= 0;
            cnt <= '0;
        end
        else begin
            cnt <= cnt + 1;
            if(cnt == CNT_MAX) begin
                clk_out <= ~clk_out;
                cnt <= 0;
            end
        end
    end
endmodule