`timescale 1ns/1ps
// =============================================================================
// Ban sua cua testbench ban gui. Giu cau truc va ten goi cu (DUT, state_name,
// check, do_reset, send_cmd, sim_camera_reg, TEST 0..4), thay doi:
//   A. Slave gia dem theo CANH LEN cua SCL (ban cu dem theo canh xuong -> lech 1 bit)
//   B. Them MONITOR tren day: dem START/STOP, dem xung SCL, kiem tra timing
//   C. send_cmd kiem tra DUT dang IDLE truoc khi gui, va tu reset khi lenh that bai
//   D. Kiem tra o_rdata o goc nhin cua HOST (sau khi giao dich xong), khong "chup" ben trong DUT
//   E. Them test: doi cong giua luc dang truyen, ghi lien tiep, bus yen, ngau nhien
//
// Chay: iverilog -g2012 -o sim/sccb.out src/sccb_master.sv sim/sccb_master_tb_fixed.sv
//       cd sim && vvp sccb.out  [+nodump] [+nrand=20]
// =============================================================================
module sccb_master_tb;

    // ===================== 0. hang so =====================
    localparam [6:0]   SLAVE_ADDR   = 7'h21;
    localparam integer T_AA_NS      = 300;      // camera dat bit sau canh xuong SCL (datasheet 100..900 ns)
    localparam         ACK_EN       = 1'b1;     // slave keo SDA xuong o bit thu 9 cua phase ghi
    localparam integer ACCEPT_LIMIT = 100;      // 100 chu ky = 1 us de FSM nhan lenh
    localparam integer DONE_LIMIT   = 300000;   // 3 ms de giao dich xong
    localparam integer MAX_PRINT    = 40;       // so loi toi da in ra

    // Gioi han toi thieu theo bang AC (ns)
    parameter real MIN_T_LOW      = 1300.0;
    parameter real MIN_T_HIGH     =  600.0;
    parameter real MIN_T_SU_STA   =  600.0;
    parameter real MIN_T_HD_STA   =  600.0;
    parameter real MIN_T_SU_DAT   =  100.0;
    parameter real MIN_T_SU_STO   =  600.0;
    parameter real MIN_T_BUF      = 1300.0;
    parameter real MIN_SCL_PERIOD = 2500.0;     // fSCL toi da 400 kHz

    // ===================== 1. tin hieu =====================
    logic       clk        = 1'b0;
    logic       arstn      = 1'b1;
    logic       i_start    = 1'b0;
    logic [1:0] i_mode     = 2'd0; // 0=NONE, 1=W_3_PHASE, 2=W_2_PHASE, 3=R_2_PHASE
    logic [7:0] i_sub_addr = 8'h00;
    logic [7:0] i_wdata    = 8'h00;

    wire [7:0] o_rdata;
    wire       o_scl;
    wire       o_sda_release;
    wire       o_busy;

    // SDA open-drain: day = 1 chi khi CA HAI ben cung tha noi
    logic slave_sda_release = 1'b1;
    wire  sda_line = o_sda_release & slave_sda_release;
    wire  scl_line = o_scl;

    always #5 clk = ~clk; // 100 MHz

    sccb_master DUT (
        .clk            (clk),
        .arstn          (arstn),
        .i_start        (i_start),
        .i_sda          (sda_line),
        .i_sub_addr     (i_sub_addr),
        .i_wdata        (i_wdata),
        .i_mode         (i_mode),
        .o_rdata        (o_rdata),
        .o_scl          (o_scl),
        .o_sda_release  (o_sda_release),
        .o_busy         (o_busy)
    );

    // Ten trang thai cho GTKWave (chuot phai -> Data Format -> ASCII)
    reg [8*16-1:0] state_name;
    always @(*) begin
        case (DUT.current_state)
            4'd0:  state_name = "IDLE";
            4'd1:  state_name = "PRE_START";
            4'd2:  state_name = "START";
            4'd3:  state_name = "SEND_ID_ADDR";
            4'd4:  state_name = "SEND_SUB_ADDR";
            4'd5:  state_name = "RCV_RD_DATA";
            4'd6:  state_name = "SEND_DATA";
            4'd7:  state_name = "BIT_9_PHASE1";
            4'd8:  state_name = "BIT_9_PHASE2";
            4'd9:  state_name = "BIT_9_PHASE3";
            4'd10: state_name = "STOP";
            default: state_name = "UNKNOWN";
        endcase
    end

    // ===================== 2. ham bao loi =====================
    // msg la vector bit (khong dung kieu string) de chay duoc ca tren Icarus cu
    integer errors = 0;
    task automatic check(input logic condition, input [8*80-1:0] msg);
        begin
            if (condition !== 1'b1) begin
                errors = errors + 1;
                if (errors <= MAX_PRINT) $display("[ERROR @ %0t] %0s", $time, msg);
            end
        end
    endtask

    integer n_timing_checks = 0;
    task automatic chk_min(input [8*16-1:0] name, input real measured, input real minv);
        begin
            n_timing_checks = n_timing_checks + 1;
            if (measured < minv) begin
                errors = errors + 1;
                if (errors <= MAX_PRINT)
                    $display("[ERROR @ %0t] timing %0s: do duoc %0.1f ns < toi thieu %0.1f ns",
                             $time, name, measured, minv);
            end
        end
    endtask

    // ===================== 3. slave gia (camera gia) =====================
    // Slave chi nhin day SDA/SCL. Nguyen tac: DEM CANH LEN SCL.
    //   canh len thu 1..8 = 8 bit du lieu (MSB truoc), canh len thu 9 = bit ACK/NA.
    //   Canh xuong NGAY SAU START khong phai la ket thuc cua bit nao, nen khong duoc dem.
    localparam [2:0] S_IDLE = 3'd0, S_RX_ID = 3'd1, S_RX_SUB = 3'd2,
                     S_RX_DATA = 3'd3, S_TX = 3'd4, S_WAIT_STOP = 3'd5;

    logic [7:0] sim_camera_reg [0:255];     // thanh ghi cua camera gia
    logic [7:0] ref_regs       [0:255];     // dap an cua testbench
    logic [2:0] s_state = S_IDLE;
    integer     s_rise  = 0;                // so canh len SCL trong byte hien tai
    logic [7:0] s_sh    = 8'h00;            // thanh ghi dich nhan
    logic [7:0] s_tx    = 8'h00;            // byte dang gui
    logic [7:0] s_ptr   = 8'h00;            // con tro thanh ghi
    logic       s_rw    = 1'b0;

    // Ghi nhan transaction gan nhat de test kiem tra
    logic [7:0] rx_byte [0:3];
    integer     rx_n       = 0;             // so byte slave nhan duoc
    logic [7:0] tx_byte    = 8'h00;         // byte slave da gui (khi doc)
    logic       is_read_op = 1'b0;
    logic       na_seen    = 1'b0;
    logic       na_val     = 1'b0;
    logic       addr_bad   = 1'b0;

    task slv_start;
        begin
            s_state = S_RX_ID; s_rise = 0; s_sh = 8'h00;
            rx_n = 0; is_read_op = 1'b0; na_seen = 1'b0; tx_byte = 8'h00; addr_bad = 1'b0;
            slave_sda_release <= 1'b1;
        end
    endtask

    task slv_stop;
        begin
            s_state = S_IDLE; s_rise = 0;
            slave_sda_release <= 1'b1;
        end
    endtask

    // Canh len SCL: BEN NHAN CHOT BIT
    task slv_scl_rise;
        begin
            if (s_state != S_IDLE && s_state != S_WAIT_STOP) begin
                s_rise = s_rise + 1;
                if (s_state == S_TX) begin
                    if (s_rise == 9) begin na_seen = 1'b1; na_val = (sda_line === 1'b1); end // NA do master lai
                end else begin
                    if (s_rise <= 8) s_sh = {s_sh[6:0], (sda_line === 1'b1)};               // MSB truoc
                end
            end
        end
    endtask

    // Canh xuong SCL: BEN GUI DOI SDA
    task slv_scl_fall;
        begin
            case (s_state)
                S_RX_ID, S_RX_SUB, S_RX_DATA: begin
                    if (s_rise == 8) begin                         // vua nhan du 8 bit
                        if (rx_n < 4) rx_byte[rx_n] = s_sh;
                        rx_n = rx_n + 1;
                        case (s_state)
                            S_RX_ID:   begin s_rw = s_sh[0]; if (s_sh[7:1] != SLAVE_ADDR) addr_bad = 1'b1; end
                            S_RX_SUB:  s_ptr = s_sh;
                            S_RX_DATA: sim_camera_reg[s_ptr] = s_sh;
                            default: ;
                        endcase
                        if (ACK_EN) slave_sda_release <= #(T_AA_NS) 1'b0;   // ACK (keo SDA xuong) sau T_AA
                    end else if (s_rise == 9) begin                 // het bit thu 9
                        slave_sda_release <= 1'b1;
                        s_rise = 0;
                        case (s_state)
                            S_RX_ID: begin
                                if (s_rw) begin                     // master doc: slave bat dau gui
                                    s_state = S_TX;
                                    s_tx = sim_camera_reg[s_ptr];
                                    tx_byte = s_tx; is_read_op = 1'b1;
                                    slave_sda_release <= #(T_AA_NS) s_tx[7];
                                end else s_state = S_RX_SUB;
                            end
                            S_RX_SUB: s_state = S_RX_DATA;
                            default: ;
                        endcase
                    end
                end
                S_TX: begin
                    if (s_rise >= 1 && s_rise <= 7) slave_sda_release <= #(T_AA_NS) s_tx[7 - s_rise];
                    else if (s_rise == 8)           slave_sda_release <= #(T_AA_NS) 1'b1; // nhuong bus cho NA
                    else if (s_rise == 9) begin slave_sda_release <= 1'b1; s_state = S_WAIT_STOP; end
                end
                default: ;
            endcase
        end
    endtask

    // ===================== 4. monitor tren day =====================
    // Chi nhin day, khong nhin ben trong DUT. Kiem tra:
    //   - moi lan SDA doi khi SCL cao chi duoc la START hoac STOP
    //   - moi transaction co dung 1 START va (9 xung SCL x so phase) + 1 xung chuan bi STOP
    //   - cac moc timing theo bang AC
    logic mon_en = 1'b0;
    logic m_scl = 1'b1, m_sda = 1'b1;
    logic scl_now, sda_now;
    logic ev_scl_rise, ev_scl_fall, ev_sda_rise, ev_sda_fall, ev_start, ev_stop;
    real  now = 0.0, t_both = 0.0;
    real  t_scl_rise = 0.0, t_scl_fall = 0.0, t_sda_change = 0.0, t_sda_rise = 0.0;
    real  t_start = 0.0, t_stop = 0.0;
    logic have_scl_rise = 1'b0, have_scl_fall = 1'b0, have_stop = 1'b0;
    logic after_start = 1'b0, in_txn = 1'b0;

    integer txn_starts = 0, txn_scl_rises = 0;
    integer exp_phases = 0;                 // send_cmd dat truoc khi gui lenh
    integer total_starts = 0, total_stops = 0, txn_checked = 0;

    task check_txn;                         // goi khi thay STOP
        begin
            txn_checked = txn_checked + 1;
            if (exp_phases != 0) begin
                if (txn_starts != 1) begin
                    errors = errors + 1;
                    if (errors <= MAX_PRINT)
                        $display("[ERROR @ %0t] so START trong transaction = %0d (mong doi 1)", $time, txn_starts);
                end
                if (txn_scl_rises != 9 * exp_phases + 1) begin
                    errors = errors + 1;
                    if (errors <= MAX_PRINT)
                        $display("[ERROR @ %0t] so xung SCL = %0d, mong doi %0d (%0d phase x 9 + 1 xung chuan bi STOP)",
                                 $time, txn_scl_rises, 9 * exp_phases + 1, exp_phases);
                end
            end
        end
    endtask

    always @(scl_line or sda_line) begin
        now     = $realtime;
        scl_now = (scl_line === 1'b1);
        sda_now = (sda_line === 1'b1);
        ev_scl_rise = scl_now & ~m_scl;
        ev_scl_fall = ~scl_now & m_scl;
        ev_sda_rise = sda_now & ~m_sda;
        ev_sda_fall = ~sda_now & m_sda;
        ev_start    = ev_sda_fall & scl_now & m_scl;    // SDA xuong khi SCL dang cao
        ev_stop     = ev_sda_rise & scl_now & m_scl;    // SDA len khi SCL dang cao

        if (mon_en) begin
            if ((ev_scl_rise | ev_scl_fall) & (ev_sda_rise | ev_sda_fall))
                check(1'b0, "SDA va SCL doi trang thai cung mot thoi diem");

            if (ev_scl_rise) begin
                check(in_txn, "SCL len khi bus ranh (chua co START)");
                if (have_scl_fall) chk_min("t_LOW", now - t_scl_fall, MIN_T_LOW);
                if (have_scl_rise) chk_min("chu ky SCL", now - t_scl_rise, MIN_SCL_PERIOD);
                if (have_scl_fall && t_sda_change > t_scl_fall)
                    chk_min("t_SU:DAT", now - t_sda_change, MIN_T_SU_DAT);
                t_scl_rise = now; have_scl_rise = 1'b1;
                if (in_txn) txn_scl_rises = txn_scl_rises + 1;
            end

            if (ev_scl_fall) begin
                check(in_txn, "SCL xuong khi bus ranh (chua co START)");
                if (have_scl_rise) chk_min("t_HIGH", now - t_scl_rise, MIN_T_HIGH);
                if (after_start) begin
                    chk_min("t_HD:STA", now - t_start, MIN_T_HD_STA);
                    after_start = 1'b0;
                end
                t_scl_fall = now; have_scl_fall = 1'b1;
            end

            if (ev_sda_fall) begin
                if (ev_start) begin
                    t_both = (t_scl_rise > t_sda_rise) ? t_scl_rise : t_sda_rise;
                    chk_min("t_SU:STA", now - t_both, MIN_T_SU_STA);
                    if (have_stop) chk_min("t_BUF", now - t_stop, MIN_T_BUF);
                    if (!in_txn) begin in_txn = 1'b1; txn_starts = 0; txn_scl_rises = 0; end
                    txn_starts = txn_starts + 1; total_starts = total_starts + 1;
                    t_start = now; after_start = 1'b1;
                end
                t_sda_change = now;
            end

            if (ev_sda_rise) begin
                t_sda_rise = now; t_sda_change = now;
                if (ev_stop) begin
                    if (have_scl_rise) chk_min("t_SU:STO", now - t_scl_rise, MIN_T_SU_STO);
                    t_stop = now; have_stop = 1'b1; total_stops = total_stops + 1;
                    check_txn;
                    in_txn = 1'b0;
                end
            end

            // slave phan ung theo cac su kien tren (cung 1 khoi -> khong bi race giua cac always)
            if (ev_start)    slv_start;
            if (ev_stop)     slv_stop;
            if (ev_scl_rise) slv_scl_rise;
            if (ev_scl_fall) slv_scl_fall;
        end

        m_scl = scl_now;
        m_sda = sda_now;
    end

    // ===================== 5. driver =====================
    integer     cmds_issued = 0;
    integer     n_cmd_fail  = 0;
    logic       cmd_failed  = 1'b0;
    logic       scramble_inputs = 1'b0;   // 1 = doi i_sub_addr/i_wdata ngay sau khi DUT nhan lenh
    logic [7:0] rdata_done  = 8'h00;      // o_rdata ngay khi o_busy xuong

    task automatic do_reset;
        begin
            mon_en  = 1'b0;
            i_start = 1'b0;
            i_mode  = 2'd0;
            #1 arstn = 1'b0;                     // canh xuong that
            repeat (10) @(posedge clk);
            #1 arstn = 1'b1;
            repeat (60) @(posedge clk);          // du lau de moi lenh NBA tre cua slave da xong
            s_state = S_IDLE; s_rise = 0;
            slave_sda_release = 1'b1;
            in_txn = 1'b0; have_stop = 1'b0; have_scl_rise = 1'b0; have_scl_fall = 1'b0; after_start = 1'b0;
            t_scl_rise = $realtime; t_sda_rise = $realtime; t_sda_change = $realtime; t_scl_fall = $realtime;
            m_scl = (scl_line === 1'b1); m_sda = (sda_line === 1'b1);
            mon_en = 1'b1;
        end
    endtask

    task automatic recover;                      // khoi phuc sau khi mot lenh that bai
        begin
            n_cmd_fail = n_cmd_fail + 1;
            do_reset();
        end
    endtask

    // Gui 1 lenh. Kiem tra DUT IDLE truoc, dat DU LIEU truoc LENH sau, cho o_busy len,
    // ha lenh, cho o_busy xuong. cmd_failed = 1 neu co timeout.
    task automatic send_cmd(
        input logic [1:0] mode,
        input logic [7:0] sub,
        input logic [7:0] wd
    );
        integer t;
        begin
            cmd_failed = 1'b0;

            // Phai IDLE truoc khi gui; neu khong, kiem tra "o_busy len 1" ben duoi se dung nham
            t = 0;
            while ((o_busy !== 1'b0) && (t < DONE_LIMIT)) begin @(posedge clk); t = t + 1; end
            check(o_busy === 1'b0, "DUT khong o IDLE truoc khi gui lenh (o_busy ket o muc cao)");
            if (o_busy !== 1'b0) cmd_failed = 1'b1;
            else begin
                exp_phases  = (mode == 2'd1) ? 3 : 2;   // so phase de monitor dem xung SCL
                cmds_issued = cmds_issued + 1;

                @(negedge clk);                          // dat lenh xa canh lay mau
                i_sub_addr = sub;                        // du lieu truoc
                i_wdata    = wd;
                i_mode     = mode;                       // lenh sau
                i_start    = 1'b1;

                t = 0;
                while ((o_busy !== 1'b1) && (t < ACCEPT_LIMIT)) begin @(posedge clk); t = t + 1; end
                check(o_busy === 1'b1, "DUT khong nhan lenh (o_busy khong len 1)");
                if (o_busy !== 1'b1) cmd_failed = 1'b1;

                @(negedge clk);                          // ha lenh sau khi DUT roi IDLE
                i_start = 1'b0;
                i_mode  = 2'd0;
                if (scramble_inputs) begin i_sub_addr = ~sub; i_wdata = ~wd; end

                if (!cmd_failed) begin
                    t = 0;
                    while ((o_busy !== 1'b0) && (t < DONE_LIMIT)) begin @(posedge clk); t = t + 1; end
                    check(o_busy === 1'b0, "Giao dich khong ket thuc (timeout 3 ms)");
                    if (o_busy !== 1'b0) cmd_failed = 1'b1;
                    rdata_done = o_rdata;
                end

                repeat (3) @(posedge clk);
                if (!cmd_failed) begin
                    check(o_scl === 1'b1,         "SCL khong ve muc cao sau giao dich");
                    check(o_sda_release === 1'b1, "Master khong tha noi SDA sau giao dich");
                end
                exp_phases = 0;
            end
        end
    endtask

    // Ghi 1 thanh ghi (3-phase) va kiem tra: byte tren day, noi dung thanh ghi cua slave
    task automatic write_reg(input [7:0] sub, input [7:0] data);
        begin
            send_cmd(2'd1, sub, data);
            if (cmd_failed) recover();
            else begin
                ref_regs[sub] = data;
                check(!addr_bad, "ID thiet bi tren day khong phai 0x21");
                if (rx_n != 3 || rx_byte[0] !== {SLAVE_ADDR, 1'b0} || rx_byte[1] !== sub || rx_byte[2] !== data) begin
                    errors = errors + 1;
                    if (errors <= MAX_PRINT)
                        $display("[ERROR @ %0t] ghi 3-phase: slave nhan %0d byte: %h %h %h, mong doi 42 %h %h",
                                 $time, rx_n, rx_byte[0], rx_byte[1], rx_byte[2], sub, data);
                end
                if (sim_camera_reg[sub] !== data) begin
                    errors = errors + 1;
                    if (errors <= MAX_PRINT)
                        $display("[ERROR @ %0t] thanh ghi %h cua slave = %h, mong doi %h",
                                 $time, sub, sim_camera_reg[sub], data);
                end
            end
        end
    endtask

    // Doc 1 thanh ghi = 2-phase write (dat con tro) + 2-phase read
    task automatic read_reg(input [7:0] sub);
        logic [7:0] expv;
        begin
            expv = ref_regs[sub];
            send_cmd(2'd2, sub, 8'h00);                   // nua 1: dat con tro
            if (cmd_failed) recover();
            else begin
                if (rx_n != 2 || rx_byte[0] !== {SLAVE_ADDR, 1'b0} || rx_byte[1] !== sub) begin
                    errors = errors + 1;
                    if (errors <= MAX_PRINT)
                        $display("[ERROR @ %0t] 2-phase write: slave nhan %0d byte: %h %h, mong doi 42 %h",
                                 $time, rx_n, rx_byte[0], rx_byte[1], sub);
                end
                send_cmd(2'd3, 8'h00, 8'h00);             // nua 2: doc
                if (cmd_failed) recover();
                else begin
                    if (!is_read_op || rx_n != 1 || rx_byte[0] !== {SLAVE_ADDR, 1'b1}) begin
                        errors = errors + 1;
                        if (errors <= MAX_PRINT)
                            $display("[ERROR @ %0t] 2-phase read: byte ID = %h (mong doi 43), so byte nhan = %0d",
                                     $time, rx_byte[0], rx_n);
                    end
                    check(na_seen && (na_val === 1'b1), "Bit thu 9 khi doc phai la NA = 1 (master phai tha noi SDA)");
                    if (tx_byte !== expv) begin
                        errors = errors + 1;
                        if (errors <= MAX_PRINT)
                            $display("[ERROR @ %0t] slave gui %h nhung mong doi %h (thanh ghi %h)", $time, tx_byte, expv, sub);
                    end
                    if (rdata_done !== expv) begin
                        errors = errors + 1;
                        if (errors <= MAX_PRINT)
                            $display("[ERROR @ %0t] o_rdata luc xong = %h, mong doi %h (thanh ghi %h)", $time, rdata_done, expv, sub);
                    end
                    repeat (50) @(posedge clk);
                    check(o_rdata === expv, "o_rdata bi thay doi/xoa khi DUT ve IDLE (host khong kip lay)");
                end
            end
        end
    endtask

    task automatic check_idle_state;
        begin
            check(o_scl === 1'b1,         "Sau reset: SCL phai o muc cao");
            check(o_sda_release === 1'b1, "Sau reset: SDA phai duoc tha noi");
            check(o_busy === 1'b0,        "Sau reset: o_busy phai bang 0");
        end
    endtask

    task automatic quiet_test;                      // khong co lenh thi bus phai yen
        integer starts0;
        begin
            starts0 = total_starts;
            i_mode = 2'd0; i_start = 1'b0;
            repeat (10000) @(posedge clk);          // 100 us
            check(total_starts == starts0, "Co START khi khong co lenh (FSM tu chay)");
            check(o_busy === 1'b0,         "o_busy = 1 khi khong co lenh");
            check(o_scl === 1'b1 && o_sda_release === 1'b1, "Bus khong o muc ranh khi khong co lenh");
        end
    endtask

    // ===================== 6. cac test =====================
    integer i, nrand, r;
    logic [7:0] rs, rd;

    initial begin
        $timeformat(-9, 0, " ns", 10);
        if (!$test$plusargs("nodump")) begin
            $dumpfile("sccb_tb.vcd");
            $dumpvars(0, sccb_master_tb);
        end
        if (!$value$plusargs("nrand=%d", nrand)) nrand = 5;

        for (i = 0; i < 256; i = i + 1) begin sim_camera_reg[i] = 8'h00; ref_regs[i] = 8'h00; end
        sim_camera_reg[8'h0A] = 8'h76; ref_regs[8'h0A] = 8'h76;   // PID
        sim_camera_reg[8'h0B] = 8'h73; ref_regs[8'h0B] = 8'h73;   // VER
        sim_camera_reg[8'h1C] = 8'h7F; ref_regs[8'h1C] = 8'h7F;   // MIDH
        sim_camera_reg[8'h1D] = 8'hA2; ref_regs[8'h1D] = 8'hA2;   // MIDL

        do_reset();

        $display("\n[TEST 0] Idle sau reset va khi khong co lenh");
        check_idle_state();
        quiet_test();

        $display("\n[TEST 1] 3-phase write: ghi 0x80 vao COM7 (0x12)");
        write_reg(8'h12, 8'h80);

        $display("\n[TEST 2] Doc PID (0x0A), mong doi 0x76");
        read_reg(8'h0A);

        $display("\n[TEST 3] Doc VER (0x0B), mong doi 0x73");
        read_reg(8'h0B);

        $display("\n[TEST 4] Ghi roi doc lai thanh ghi 0x11");
        write_reg(8'h11, 8'h3F);
        read_reg(8'h11);

        $display("\n[TEST 5] Gia tri bien: 0x00, 0xFF, 0x55, 0xAA");
        write_reg(8'h40, 8'h00);
        write_reg(8'h41, 8'hFF);
        write_reg(8'h42, 8'h55);
        write_reg(8'h43, 8'hAA);
        read_reg(8'h41);
        read_reg(8'h43);

        $display("\n[TEST 6] Host doi cong giua luc dang truyen (DUT phai chot tham so 1 lan)");
        scramble_inputs = 1'b1;
        write_reg(8'h20, 8'h99);
        scramble_inputs = 1'b0;

        $display("\n[TEST 7] Ghi lien tiep (kiem tra t_BUF giua cac giao dich)");
        for (i = 0; i < 4; i = i + 1) write_reg(8'h30 + i, 8'hF0 + i);

        $display("\n[TEST 8] Ngau nhien %0d lenh", nrand);
        for (i = 0; i < nrand; i = i + 1) begin
            r  = $urandom;
            rs = $urandom;
            rd = $urandom;
            if (r[0]) write_reg(rs, rd);
            else      read_reg(rs);
        end

        $display("\n[TEST 9] Bus yen sau khi xong, so STOP = so lenh");
        quiet_test();
        repeat (2000) @(posedge clk);
        if (n_cmd_fail == 0)
            check(total_stops == cmds_issued, "So STOP tren day khac so lenh da gui (DUT chay thua hoac thieu)");

        $display("\n==================================================");
        $display("so lenh da gui          : %0d", cmds_issued);
        $display("transaction da kiem tra : %0d", txn_checked);
        $display("phep do timing          : %0d", n_timing_checks);
        $display("lenh bi that bai        : %0d", n_cmd_fail);
        $display("so loi                  : %0d", errors);
        if (errors == 0 && n_cmd_fail == 0 && n_timing_checks > 0 && txn_checked >= cmds_issued)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> TEST FAILED: %0d loi <<<", errors);
        $display("==================================================\n");
        #1000;
        $finish;
    end

    // Watchdog
    initial begin
        #200_000_000;
        $display("LOI: watchdog 200 ms, mo phong bi treo");
        $finish;
    end

endmodule