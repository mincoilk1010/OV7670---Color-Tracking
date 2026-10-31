module vga_timing (
    input wire clk,
    input wire arstn,
    output logic hsync, //active-low
    output logic vsync, //active low
    output logic [9:0] x, //horizontal (0-799)
    output logic [9:0] y, //veritcal (0-524)
    output logic active
); 
    localparam TOTAL_H = 800, ACTIVE_H = 640, FRONT_PORCH_H = 16, SYNC_H = 96, BACK_PORCH_H = 48;
    localparam TOTAL_V = 525, ACTIVE_V = 480, FRONT_PORCH_V = 10, SYNC_V = 2, BACK_PORCH_V = 33;

    always_ff @(posedge clk or negedge arstn) begin
        if(!arstn) begin
            x <= 0;
            y <= 0;
        end
        else begin
            x <= x + 1;
            if(x == TOTAL_H - 1) begin
                x <= 0;
                y <= y + 1;
                if(y == TOTAL_V - 1) begin
                    y <= 0;
                end
            end
        end
    end

    assign active = (x < ACTIVE_H && y < ACTIVE_V) ? 1'b1 : 1'b0;
    assign hsync = (x < (ACTIVE_H + FRONT_PORCH_H) || x >= (TOTAL_H - BACK_PORCH_H)) ? 1'b1 : 1'b0;
    assign vsync = (y < (ACTIVE_V + FRONT_PORCH_V) || y >= (TOTAL_V - BACK_PORCH_V)) ? 1'b1 : 1'b0;
endmodule