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

    localparam int CNT_BUF = ((T_BUF * CLK_FREQ_KHZ)/1000000) - 1; 
    localparam int CNT_START = ((T_STA * CLK_FREQ_KHZ)/1000000) - 1; 
    localparam int CNT_STOP = ((T_STOP * CLK_FREQ_KHZ)/1000000) - 1; 
    localparam int CNT_HALF_SCL_CLK = (CLK_FREQ_KHZ /(2*SCL_CLK_FREQ_KHZ)) - 1; 
    localparam int CNT_HD_DAT = (T_HD_DAT * CLK_FREQ_KHZ)/1000000 - 1; 
    localparam int CNT_SU_DAT = ((T_SU_DAT * CLK_FREQ_KHZ)/1000000) - 1; 


    typedef enum logic [3:0] {
        IDLE,
        PRE_START,
        START,
        SEND_ID_ADDR,
        SEND_SUB_ADDR,
        RCV_RD_DATA,
        SEND_DATA,
        BIT_9, 
        STOP,
        STOP_WAIT
    } state_t;

    localparam NONE = 2'd0;
    localparam W_3_PHASE = 2'd1;
    localparam W_2_PHASE = 2'd2;
    localparam R_2_PHASE = 2'd3;

    logic [15:0] cnt; //must be fix!!!!!
    state_t current_state, next_state;
    logic [1:0] mode_reg;
    logic [7:0] wdata_reg;
    logic [7:0] sub_addr_reg;

    wire [7:0] slave_id_addr = (mode_reg == R_2_PHASE) ? {SLAVE_ADDR, 1'b1} : {SLAVE_ADDR, 1'b0};

    //state register
    always_ff @(posedge clk or negedge arstn) begin
        if(~arstn) begin
            current_state <= IDLE;
            cnt <= 0;
            mode_reg <= NONE;
            wdata_reg <= 0;
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
            cnt <= cnt + 1;
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
                if(cnt == CNT_START) begin
                    next_state = SEND_ID_ADDR;
                end
            end
            SEND_ID_ADDR: begin
                
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
                    end
                end
                SEND_ID_ADDR: begin
                    
                end
            endcase
        end
    end

    assign o_busy = (current_state != IDLE) ? 1'b1 : 1'b0;
endmodule 