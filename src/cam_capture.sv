//frame buffer
`timescale 1ns/1ps

module cam_capture (
    input pclk,
    input arstn,
    input i_config_done,
    input [7:0] i_pixel_byte,
    input i_href,
    input i_vsync, //default setting: vsync is sent with negedge of pclk

    output logic [11:0] o_pixel_data, //12 bit RGB444: {RRRR, GGGG, BBBB}
    output logic [18:0] o_pixel_addr //800x525 pixels -> 420 000 pixels -> choose 19 bits width
);

typedef enum logic [1:0] {
    CONFIG_WAIT,
    IDLE,
    CAPTURE
} state_t;

state_t current_state, next_state;
wire frame_start, frame_end;

logic prev_vsync, current_vsync;
logic r_half_data; //flag choose MSB or LSB -> 1 = [11:6] , 0 = [5:0]  
logic [3:0] pixel_data;

always @(posedge pclk or negedge arstn) begin
    if(!arstn) begin
        prev_vsync <= 1'b0;
        current_vsync <= 1'b0;
    end
    else begin
        prev_vsync <= current_vsync;
        current_vsync <= i_vsync;
    end
end

assign frame_start = (prev_vsync) && (~current_vsync);
assign frame_end = (~prev_vsync) && (current_vsync);

//state register
always_ff @(posedge pclk or negedge arstn) begin
    if(!arstn) begin
        current_state <= CONFIG_WAIT;
    end
    else begin
        current_state <= next_state;
    end
end

//next state logic
always_comb begin 
    next_state = current_state;
    case(current_state)
        CONFIG_WAIT: begin
            if(i_config_done && frame_start) begin
                next_state = IDLE;
            end
        end
        IDLE: begin
            if(frame_start) begin
                next_state = CAPTURE;
            end
        end
        CAPTURE: begin
            if(frame_end) begin
                next_state = IDLE;
            end
        end
        default: begin
            next_state = CONFIG_WAIT;
        end
    endcase
end

//output logic
always_ff @(posedge pclk or negedge arstn) begin
    if(!arstn) begin
        o_pixel_data <= 0;
        o_pixel_addr <= 0;
        r_half_data <= 1'b0;
        pixel_data <= 4'b0;
    end
    else begin
        case(current_state)
            CONFIG_WAIT: begin
                o_pixel_data <= 0;
                o_pixel_addr <= 0;
                r_half_data <= 1'b0;
            end
            IDLE: begin
                o_pixel_addr <= 0;
                o_pixel_data <= 0;
                r_half_data <= 1'b0;
            end
            CAPTURE: begin
                if(i_href) begin
                    r_half_data <= ~r_half_data;
                    if(~r_half_data) begin
                        pixel_data <= i_pixel_byte[3:0];
                    end
                    else begin
                        o_pixel_addr <= o_pixel_addr + 1;
                        o_pixel_data <= {pixel_data, i_pixel_byte};
                    end
                end
                else begin
                    r_half_data <= 1'b0;
                end
            end
            default: begin
                o_pixel_data <= 0;
                o_pixel_addr <= 0;
                r_half_data <= 1'b0;
            end
        endcase
    end
end
endmodule