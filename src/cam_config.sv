`timescale 1ns/1ps
module cam_config 
#(
    parameter CLK_IN = 100_000_000
)
(
    input clk, 
    input arstn,
    input i_config_start,
    input i_sccb_ready,
    input i_sccb_done,
    input [15:0] i_rom_data,
    output logic [7:0] o_rom_addr,
    output logic o_sccb_start,
    output logic [7:0] o_sccb_sub_addr,
    output logic [1:0] o_sccb_mode,
    output logic [7:0] o_sccb_data,
    output logic o_config_done
);
    typedef enum logic [2:0] {
        IDLE,
        //RD_ROM,
        RD_ROM_AND_PREPARE_SCCB,
        SEND,
        WAIT_DELAY,
        STOP
    } state_t;

    localparam CNT_RESET_DELAY = (CLK_IN*10/1000) - 1; //10ms delay
    state_t current_state, next_state;
    logic [$clog2(CNT_RESET_DELAY + 1) - 1: 0] cnt;
    logic [15:0] rom_data_reg;

    //cnt register
    always_ff @(posedge clk or negedge arstn) begin
        if(~arstn) begin
            cnt <= 0;
        end
        else begin
            if(current_state != next_state) begin
                cnt <= 0;
            end 
            else begin
                cnt <= cnt + 1;
            end
        end
    end

    //state register
    always_ff @(posedge clk or negedge arstn) begin
        if(~arstn) begin
            current_state <= IDLE;
        end
        else begin
            if(current_state != next_state) begin
                current_state <= next_state;
            end
        end
    end

    //next state logic
    always_comb begin
        next_state = current_state;
        case(current_state)
            IDLE: begin
                if(i_config_start && i_sccb_ready) begin
                    next_state = RD_ROM_AND_PREPARE_SCCB;
                end
            end
            RD_ROM_AND_PREPARE_SCCB: begin
                if(rom_data_reg == 16'hFF_FF) begin
                    next_state = STOP;
                end
                else begin
                    if(o_sccb_start == 1'b1) begin
                        next_state = SEND;
                    end
                end
            end
            SEND: begin
                if(i_sccb_done) begin
                    if(i_rom_data == 16'h12_80) begin
                        next_state = WAIT_DELAY;
                    end
                    else begin
                        next_state = RD_ROM_AND_PREPARE_SCCB;
                    end
                end
            end
            WAIT_DELAY: begin
                if(cnt == CNT_RESET_DELAY) begin
                    next_state = RD_ROM_AND_PREPARE_SCCB;
                end
            end
            STOP: begin
                next_state = STOP;
            end
            default: next_state = IDLE;
        endcase
    end

    //output logic 
    always @(posedge clk or negedge arstn) begin
        if(~arstn) begin
            o_rom_addr <= 0;
            o_sccb_start <= 0;
            o_sccb_sub_addr <= 0;
            o_sccb_mode <= 0;
            o_sccb_data <= 0;
            rom_data_reg <= 0;
        end
        else begin
            case(current_state)
                IDLE: begin
                    o_rom_addr <= 0;
                    o_sccb_start <= 0;
                    o_sccb_sub_addr <= 0;
                    o_sccb_mode <= 0;
                    o_sccb_data <= 0;
                    rom_data_reg <= 0;
                    o_config_done <= 0;
                end
                RD_ROM_AND_PREPARE_SCCB: begin
                    if(cnt == 'd1) begin
                        rom_data_reg <= i_rom_data;
                    end
                    else begin
                        if(cnt > 'd1 && rom_data_reg != 16'hFF_FF) begin
                            o_sccb_sub_addr <= rom_data_reg[15:8];
                            o_sccb_data <= rom_data_reg[7:0];
                            if(i_sccb_ready) begin
                                o_sccb_start <= 1;
                                o_sccb_mode <= 2'd1;
                            end
                        end
                    end
                end
                SEND: begin
                    o_sccb_start <= 0;
                    if(i_sccb_done) begin
                        o_sccb_sub_addr <= 0;
                        o_sccb_mode <= 0;
                        o_sccb_data <= 0;
                        rom_data_reg <= 0;
                        o_config_done <= 0;
                        o_rom_addr <= o_rom_addr + 1;
                    end
                end
                STOP: begin
                    o_config_done <= 1;
                    o_rom_addr <= 0;
                    o_sccb_start <= 0;
                    o_sccb_sub_addr <= 0;
                    o_sccb_mode <= 0;
                    o_sccb_data <= 0;
                end
            endcase
        end
    end
endmodule 