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
 
    input i_start,
    input i_sda,
    input logic [7:0] i_sub_addr,
    input logic [7:0] i_wdata,
    input logic [1:0] i_mode, //4 mode: 3 phase write data, 2 phase write data, 2 phase read data, do nothing

    output logic [7:0] o_rdata,
    output logic o_scl,
    output logic o_sda_release, //1 release, 0 pull down
    output logic o_done,
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
        STOP
    } state_t;

    localparam NONE = 2'd0;
    localparam W_3_PHASE = 2'd1;
    localparam W_2_PHASE = 2'd2;
    localparam R_2_PHASE = 2'd3;

    logic [15:0] cnt; //must be fix!!!!!
    logic [2:0] bit_cnt;
    state_t current_state, next_state;
    logic [1:0] mode_reg;
    logic [7:0] wdata_reg;
    logic [7:0] sub_addr_reg;
    logic current_scl_clk_flag, next_scl_clk_flag;

    wire [7:0] slave_id_addr = (mode_reg == R_2_PHASE) ? {SLAVE_ADDR, 1'b1} : {SLAVE_ADDR, 1'b0};
    logic [7:0] shift_left_register;
    logic [7:0] shift_rcvdata_register;

    //state register
    always_ff @(posedge clk or negedge arstn) begin
        if(~arstn) begin
            current_state <= IDLE;
            cnt <= 0;
            mode_reg <= NONE;
            wdata_reg <= 0;
            current_scl_clk_flag <= 0;
        end
        else begin
            current_scl_clk_flag <= next_scl_clk_flag;
            if(current_state == IDLE && i_start) begin
                mode_reg <= i_mode;
                wdata_reg <= i_wdata;
                sub_addr_reg <= i_sub_addr;
            end
            //current_state <= next_state;
            if(next_state != current_state) begin
                current_state <= next_state;
                cnt <= 0;
                //bit_cnt <= 0;
            end 
            else begin
                if(current_state != IDLE && current_state != PRE_START && current_state != START && current_state != STOP) begin
                    // if(cnt == CNT_HALF_SCL_CLK) begin
                    //     cnt <= cnt + 1;
                    // end
                    if(cnt == CNT_SCL_CLK) begin
                        cnt <= 0;
                        //bit_cnt <= bit_cnt + 1;
                    end
                    else begin
                        cnt <= cnt + 1;
                    end
                end
                else begin
                    cnt <= cnt + 1;
                end
            end
        end
    end

    //update scl clk flag
    always_comb begin
        if(current_state != IDLE && current_state != PRE_START && current_state != START && current_state != STOP) begin
            if(cnt == CNT_HALF_SCL_CLK || cnt == CNT_SCL_CLK) begin
                next_scl_clk_flag = ~current_scl_clk_flag;
            end
            else begin
                next_scl_clk_flag = current_scl_clk_flag;
            end
        end
        else begin
            next_scl_clk_flag = current_scl_clk_flag;
        end
    end

    //next state logic
    always_comb begin
        next_state = current_state;
        case(current_state) 
            IDLE: begin
                if(i_mode != NONE && i_start) begin
                    next_state = PRE_START;
                end
            end
            PRE_START: begin
                if(cnt == CNT_BUF) begin
                    next_state = START;
                end
            end
            START: begin
                if(cnt == CNT_SCL_CLK) begin
                    next_state = SEND_ID_ADDR;
                end
            end
            SEND_ID_ADDR: begin
                if(bit_cnt == 3'd7 && cnt == CNT_SCL_CLK) begin
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
                if(bit_cnt == 3'd7 && cnt == CNT_SCL_CLK) begin
                    next_state = BIT_9_PHASE2;
                end
            end
            RCV_RD_DATA: begin
                if(bit_cnt == 3'd7 && cnt == CNT_SCL_CLK) begin
                    next_state = BIT_9_PHASE2;
                end
            end
            BIT_9_PHASE2: begin
                if(cnt == CNT_SCL_CLK) begin
                    if(mode_reg == W_3_PHASE) begin
                        next_state = SEND_DATA;
                    end
                    else if(mode_reg == W_2_PHASE || mode_reg == R_2_PHASE) begin
                        next_state = STOP;
                    end
                end
            end
            SEND_DATA: begin
                if(bit_cnt == 3'd7 && cnt == CNT_SCL_CLK) begin
                    next_state = BIT_9_PHASE3;
                end
            end
            BIT_9_PHASE3: begin
                if(cnt == CNT_SCL_CLK) begin
                    next_state = STOP;
                end
            end
            STOP: begin
                if(cnt == CNT_SCL_CLK) begin
                    next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end
    
    //output logic
    always_ff @(posedge clk or negedge arstn) begin
        if(~arstn) begin
            o_scl <= 1;
            o_sda_release <= 1;
            bit_cnt <= 0;
        end
        else begin
            o_done <= 1'b0;
            if(current_state == STOP && next_state == IDLE) begin
                o_done <= 1'b1;
                o_rdata <= shift_rcvdata_register;
            end
            if(current_state != next_state) begin
                bit_cnt <= 0;
            end
            case(current_state)
                IDLE: begin
                    o_scl <= 1;
                    o_sda_release <= 1;
                end
                PRE_START: begin
                    o_scl <= 1;
                    o_sda_release <= 1;
                end
                START: begin
                    o_sda_release <= 0;
                    if(cnt == CNT_START) begin
                        o_scl <= 0;
                        shift_left_register <= slave_id_addr;
                    end
                end
                SEND_ID_ADDR: begin
                    if(cnt == CNT_HD_DAT) begin
                        o_sda_release <= (shift_left_register[7]);
                    end
                    if(cnt == CNT_SCL_CLK) begin
                        shift_left_register <= {shift_left_register[6:0], 1'b0};
                        bit_cnt <= bit_cnt + 1;
                    end
                    o_scl <= current_scl_clk_flag;
                end
                BIT_9_PHASE1: begin
                    o_scl <= current_scl_clk_flag;
                    o_sda_release <= 1;
                    if(mode_reg == W_3_PHASE || mode_reg == W_2_PHASE) begin
                        shift_left_register <= sub_addr_reg;
                    end
                end
                SEND_SUB_ADDR: begin
                    if(cnt == CNT_HD_DAT) begin
                        o_sda_release <= (shift_left_register[7]);
                    end
                    if(cnt == CNT_SCL_CLK) begin
                        shift_left_register <= {shift_left_register[6:0], 1'b0};
                        bit_cnt <= bit_cnt + 1;
                    end
                    o_scl <= current_scl_clk_flag;
                end
                RCV_RD_DATA: begin
                    o_sda_release <= 1'b1;
                    if(cnt == CNT_HALF_SCL_CLK + CNT_HD_DAT) begin
                        shift_rcvdata_register <= {shift_rcvdata_register[6:0], i_sda};
                        // bit_cnt <= bit_cnt + 1;
                    end
                    if(cnt == CNT_SCL_CLK) begin
                        bit_cnt <= bit_cnt + 1; 
                    end
                    o_scl <= current_scl_clk_flag;
                end
                BIT_9_PHASE2: begin
                    o_scl <= (current_scl_clk_flag) ? 1'b1 : 1'b0;
                    o_sda_release <= 1;
                    if(mode_reg == W_3_PHASE) begin
                        shift_left_register <= wdata_reg;
                    end
                end
                SEND_DATA: begin //PHASE 3
                    if(cnt == CNT_HD_DAT) begin
                        o_sda_release <= (shift_left_register[7]);
                    end
                    if(cnt == CNT_SCL_CLK) begin
                        shift_left_register <= {shift_left_register[6:0], 1'b0};
                        bit_cnt <= bit_cnt + 1;
                    end
                    o_scl <= current_scl_clk_flag;
                end
                BIT_9_PHASE3: begin
                    o_scl <= current_scl_clk_flag;
                    o_sda_release <= 1;
                end
                STOP: begin
                    if(cnt < CNT_HD_DAT) begin
                        o_scl <= 0;
                        o_sda_release <= 1;
                    end
                    else if(cnt >= CNT_HD_DAT && cnt < CNT_HALF_SCL_CLK) begin
                        o_scl <= 0;
                        o_sda_release <= 0;
                    end
                    else if(cnt >= CNT_HALF_SCL_CLK && cnt < CNT_HALF_SCL_CLK + (CNT_HALF_SCL_CLK/2)) begin
                        o_scl <= 1;
                        o_sda_release <= 0;
                    end
                    else begin
                        o_scl <= 1;
                        o_sda_release <= 1;
                    end
                end
                default: begin
                    o_sda_release <= 1;
                    o_scl <= 1;
                    o_rdata <= '0;
                end
            endcase
        end
    end

    assign o_busy = (current_state != IDLE) ? 1'b1 : 1'b0;
endmodule 