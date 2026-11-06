module vga_timing (
    input wire clk,
    input wire arstn,
    output logic hsync, //active-low
    output logic vsync, //active low
    output logic [9:0] h_count, //horizontal (0-799)
    output logic [9:0] v_count, //veritcal (0-524)
    output logic active
); 
    localparam TOTAL_H = 800, ACTIVE_H = 640, FRONT_PORCH_H = 16, SYNC_H = 96, BACK_PORCH_H = 48;
    localparam TOTAL_V = 525, ACTIVE_V = 480, FRONT_PORCH_V = 10, SYNC_V = 2, BACK_PORCH_V = 33;

    always_ff @(posedge clk or negedge arstn) begin
        if(!arstn) begin
            h_count <= 0;
            v_count <= 0;
        end
        else begin
            h_count <= h_count + 1;
            if(h_count == TOTAL_H - 1) begin
                h_count <= 0;
                v_count <= v_count + 1;
                if(v_count == TOTAL_V - 1) begin
                    v_count <= 0;
                end
            end
        end
    end

    assign active = (h_count < ACTIVE_H && v_count < ACTIVE_V) ? 1'b1 : 1'b0;
    assign hsync = (h_count < (ACTIVE_H + FRONT_PORCH_H) || h_count >= (TOTAL_H - BACK_PORCH_H)) ? 1'b1 : 1'b0;
    assign vsync = (v_count < (ACTIVE_V + FRONT_PORCH_V) || v_count >= (TOTAL_V - BACK_PORCH_V)) ? 1'b1 : 1'b0;
endmodule