`timescale 1ns/1ps

module sccb_master
#(
    parameter logic [6:0] SLAVE_ADDR = 7'h21, //OV7670 addr = {7'h21, R/W} W = 0, R = 1
    parameter T_BUF = 2000, //T_BUF(min) = 1.3 us -> pick 2 us = 2000 ns
    parameter T_STA = 1000, //T_SU:STA and T_HD:STA(min) = 600ns -> pick 1000ns 
    parameter CLK_FREQ_KHZ = 100000, //100 Mhz = 100 000 KHz * 10^3
    parameter SCL_CLK_FREQ_KHZ = 200, //FREQ SIO_C (SCL) max = 400khz -> pick 200 KHz = 200 * 10^3
    parameter T_STOP = 1000, //T_SU:STOP(min) = 600 ns -> pick 1000 ns
    parameter T_HD_DAT = 1000, //T_HD:DAT(min) = 0 us -> pick 1 us = 1000 ns
    parameter T_SU_DAT = 200 //T_SU:DAT(min) = 100ns -> pick 200 ns
) 
(
    input wire clk, //100Mhz
    input wire arstn, 
 
    input i_ida,
    input logic [7:0] i_sub_addr,
    input logic [7:0] i_wdata,
    input logic [1:0] i_mode, //4 mode: 3 phase write data, 2 phase write data, 2 phase read data, do nothing

    output logic [7:0] o_rdata,
    output logic o_scl,
    output logic o_sda_release, //1 release, 0 pull down
    output logic o_busy
);

    localparam int CNT_BUF = ((T_BUF * CLK_FREQ_KHZ)/1000000) - 1; //199
    localparam int CNT_START = ((T_STA * CLK_FREQ_KHZ)/1000000) - 1; //99
    localparam int CNT_STOP = ((T_STOP * CLK_FREQ_KHZ)/1000000) - 1; //99
    localparam int CNT_HALF_SCL_CLK = (CLK_FREQ_KHZ /(2*SCL_CLK_FREQ_KHZ)) - 1; //249
    localparam int CNT_SCL_CLK = (CNT_HALF_SCL_CLK + 1)*2 -1; //499
    localparam int CNT_HD_DAT = (T_HD_DAT * CLK_FREQ_KHZ)/1000000 - 1; //99
    localparam int CNT_SU_DAT = ((T_SU_DAT * CLK_FREQ_KHZ)/1000000) - 1; //19


    typedef enum logic [3:0] {
        IDLE,
        PRE_START,
        START,
        SEND_ID_ADDR,
        SEND_SUB_ADDR,
        RCV_RD_DATA,
        SEND_DATA,
        BIT_9_PHASE1,
        BIT_9_PHASE2,
        BIT_9_PHASE3, 
        STOP,
        STOP_WAIT
    } state_t;

    localparam NONE = 2'd0;
    localparam W_3_PHASE = 2'd1;
    localparam W_2_PHASE = 2'd2;
    localparam R_2_PHASE = 2'd3;

    logic [15:0] cnt; //must be fix!!!!!
    logic [2:0] bit_sent_cnt;
    state_t current_state, next_state;
    logic [1:0] mode_reg;
    logic [7:0] wdata_reg;
    logic [7:0] sub_addr_reg;
    logic scl_clk_rise_flag;

    wire [7:0] slave_id_addr = (mode_reg == R_2_PHASE) ? {SLAVE_ADDR, 1'b1} : {SLAVE_ADDR, 1'b0};
    logic [7:0] shift_left_register;

    //state register
    always_ff @(posedge clk or negedge arstn) begin
        if(~arstn) begin
            current_state <= IDLE;
            cnt <= 0;
            mode_reg <= NONE;
            wdata_reg <= 0;
            scl_clk_rise_flag <= 0;
        end
        else begin
            //current_state <= next_state;
            if(next_state != current_state) begin
                current_state <= next_state;
                mode_reg <= i_mode;
                wdata_reg <= i_wdata;
                sub_addr_reg <= i_sub_addr;
                cnt <= 0;
            end
            if(cnt == CNT_HALF_SCL_CLK) begin
                cnt <= cnt + 1;
                scl_clk_rise_flag <= ~scl_clk_rise_flag;
            end
            else if(cnt == CNT_SCL_CLK) begin
                cnt <= 0;
                scl_clk_rise_flag <= ~scl_clk_rise_flag;
            end
            else begin
                cnt <= cnt + 1;
            end
        end
    end

    //next state logic
    always_comb begin
        case(current_state) 
            IDLE: begin
                if(mode_reg != NONE) begin
                    next_state = PRE_START;
                end
            end
            PRE_START: begin
                if(cnt == CNT_START) begin
                    next_state = START;
                end
            end
            START: begin
                if(cnt == CNT_SCL_CLK) begin
                    next_state = SEND_ID_ADDR;
                end
            end
            SEND_ID_ADDR: begin
                if(bit_sent_cnt == 3'd7) begin
                    next_state = BIT_9_PHASE1;
                end
            end
            BIT_9_PHASE1: begin
                if(cnt == CNT_SCL_CLK) begin
                    if(mode_reg == W_3_PHASE || mode_reg == W_2_PHASE) begin
                        next_state = SEND_SUB_ADDR;
                    end
                    else if(mode_reg == R_2_PHASE) begin
                        next_state = RCV_RD_DATA;
                    end
                end
            end
            SEND_SUB_ADDR: begin

            end
            RCV_RD_DATA: begin
                
            end
            BIT_9_PHASE2: begin
            end
            SEND_DATA: begin
                
            end
            BIT_9_PHASE3: begin
            end
            default: next_state = IDLE;
        endcase
    end
    
    //output logic
    always_ff @(posedge clk or negedge arstn) begin
        if(~arstn) begin
            o_scl <= 1;
            o_sda_release <= 1;
            o_rdata <= 0;
            bit_sent_cnt <= 0;
        end
        else begin
            case(next_state)
                IDLE: begin
                    o_scl <= 1;
                    o_sda_release <= 1;
                    o_rdata <= 0;
                end
                PRE_START: begin
                    o_scl <= 1;
                    o_sda_release <= 1;
                    o_rdata <= 0;
                end
                START: begin
                    o_sda_release <= 0;
                    if(cnt == CNT_START) begin
                        o_scl <= 0;
                        shift_left_register <= slave_id_addr;
                    end
                end
                SEND_ID_ADDR: begin
                    if(cnt == CNT_SCL_CLK) begin
                        o_sda_release <= (shift_left_register[7]) ? 1'b1 : 1'b0;
                        shift_left_register <= shift_left_register << 1;
                    end
                    o_scl <= (scl_clk_rise_flag) ? 1'b1 : 1'b0;
                    bit_sent_cnt <= bit_sent_cnt + 1;
                end
                BIT_9_PHASE1: begin
                    o_scl <= (scl_clk_rise_flag) ? 1'b1 : 1'b0;
                    o_sda_release <= 1;
                    if(mode_reg == W_3_PHASE || mode_reg == W_2_PHASE) begin
                        shift_left_register <= sub_addr_reg;
                    end
                    // else if(mode_reg == R_2_PHASE) begin
                    //     shift_left_register <= 
                    // end
                end
                SEND_SUB_ADDR: begin
                    if(cnt == CNT_SCL_CLK) begin
                        o_sda_release <= (shift_left_register[7]) ? 1'b1 : 1'b0;
                        shift_left_register <= shift_left_register << 1;
                    end
                    o_scl <= (scl_clk_rise_flag) ? 1'b1 : 1'b0;
                    bit_sent_cnt <= bit_sent_cnt + 1;
                end
                RCV_RD_DATA: begin
                    
                end
                BIT_9_PHASE2: begin
                end
                SEND_DATA: begin
                    
                end
                BIT_9_PHASE3: begin
                end
            endcase
        end
    end

    assign o_busy = (current_state != IDLE) ? 1'b1 : 1'b0;
endmodule 