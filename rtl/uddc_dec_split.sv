// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module uddc_dec_split
    #(
        parameter int unsigned UNIT_ID_W = 4,
        parameter int unsigned UNIT_SLOTS = 8
    )
    (
        input logic clk,
        input logic rst_n,
        input logic s_valid,
        output logic s_ready,
        input logic [255:0] s_data,
        input logic s_sop,
        input logic s_last,
        input logic s_has_data,
        input logic [3:0] s_cbmd,
        output logic ctx_valid,
        input logic ctx_ready,
        output logic [UNIT_ID_W - 1:0] ctx_unit_id,
        output logic [3:0] ctx_cbmd,
        output logic [1023:0] ctx_raw,
        output logic pkg_valid,
        input logic pkg_ready,
        output logic [UNIT_ID_W - 1:0] pkg_unit_id,
        output logic pkg_pkg_id,
        output logic [3:0] pkg_cbmd,
        output logic [767:0] pkg_region,
        output logic [6:0] pkg_available_bytes,
        output logic pkg_final,
        output logic clear_valid,
        input logic clear_ready,
        output logic [UNIT_ID_W - 1:0] clear_unit_id,
        output logic [3:0] clear_index,
        input logic retire_valid,
        input logic [UNIT_ID_W - 1:0] retire_unit_id
    );

    function automatic int occupied_bytes(input logic [3:0] cbmd);
        case (cbmd)
            1: begin
                return 32;
            end
            2, 3, 4: begin
                return 64;
            end
            5: begin
                return 96;
            end
            0: begin
                return 128;
            end
            default: begin
                return 0;
            end
        endcase
    endfunction
    logic [UNIT_SLOTS - 1:0] allocated, complete;
    logic [1023:0] data_mem[0:UNIT_SLOTS - 1];
    logic [3:0] cbmd_mem[0:UNIT_SLOTS - 1];
    integer wr_slot, dispatch_slot;
    localparam int unsigned STREAM_DATA_BITS = 256;
    localparam int unsigned STREAM_BYTES = STREAM_DATA_BITS / 8;
    localparam int unsigned UNIT_BEATS = 1024 / STREAM_DATA_BITS;
    localparam int unsigned BEAT_WIDTH = $clog2(UNIT_BEATS);
    localparam logic [BEAT_WIDTH - 1:0] LAST_UNIT_BEAT = BEAT_WIDTH'(UNIT_BEATS - 1);
    logic [BEAT_WIDTH - 1:0] beat;
    logic collecting;
    localparam logic [1:0] DISPATCH_CTX = 2'd0;
    localparam logic [1:0] DISPATCH_PKG0 = 2'd1;
    localparam logic [1:0] DISPATCH_PKG1 = 2'd2;
    localparam logic [1:0] DISPATCH_CLEAR = 2'd3;
    // All binary encodings are used; unknown state bits require reset.
    logic [1:0] dispatch_state;
    logic [UNIT_SLOTS - 1:0] started;
    logic [7:0] received_bytes[0:UNIT_SLOTS - 1];
    logic [7:0] offered_bytes;
    logic load_snapshot;
    logic finish_request;
    // A registered immutable snapshot prevents incoming beats changing a stalled request.
    assign load_snapshot = rst_n && !pkg_valid &&
        ((ctx_valid && ctx_ready && ctx_cbmd >= 1 && ctx_cbmd <= 5) ||
        (dispatch_state == DISPATCH_PKG0 && received_bytes[dispatch_slot] > offered_bytes) ||
        (dispatch_state == DISPATCH_PKG1 && complete[dispatch_slot]));
    assign finish_request = pkg_valid && pkg_ready && pkg_final;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            started <= '0;
        end
        else begin
            if (ctx_valid && ctx_ready) begin
                started[dispatch_slot] <= 0;
            end
            if (s_valid && s_ready && !collecting) begin
                started[wr_slot] <= 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            received_bytes <= '{default: '0};
        end
        else begin
            if (s_valid && s_ready) begin
                received_bytes[wr_slot] <= s_has_data ? 8'($unsigned((int'(beat) + 1) * 32)) : 8'd0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            offered_bytes <= 0;
        end
        else begin
            if (load_snapshot) begin
                offered_bytes <= received_bytes[dispatch_slot];
            end
            else begin
                if (ctx_valid && ctx_ready) begin
                    offered_bytes <= 0;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkg_valid <= 0;
        end
        else begin
            if (load_snapshot) begin
                pkg_valid <= 1;
            end
            else begin
                if (pkg_valid && pkg_ready) begin
                    pkg_valid <= 0;
                end
            end
        end
    end

    function automatic int advance(input int slot);
        return slot == int'(UNIT_SLOTS) - 1 ? 0 : slot + 1;
    endfunction
    assign s_ready = rst_n && (collecting || !allocated[wr_slot]);
    assign ctx_valid = rst_n && started[dispatch_slot] &&
        (cbmd_mem[dispatch_slot] != 0 || complete[dispatch_slot]) && dispatch_state == DISPATCH_CTX;
    assign ctx_unit_id = UNIT_ID_W'($unsigned(dispatch_slot));
    assign ctx_cbmd = cbmd_mem[dispatch_slot];
    assign ctx_raw = ctx_cbmd == 0 ? data_mem[dispatch_slot] : '0;
    assign clear_valid = rst_n && dispatch_state == DISPATCH_CLEAR;
    assign clear_unit_id = UNIT_ID_W'($unsigned(dispatch_slot));
    assign clear_index = cbmd_mem[dispatch_slot] - 4'd6;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            allocated <= '0;
        end
        else begin
            if (retire_valid) begin
                allocated[retire_unit_id] <= 0;
            end
            if (s_valid && s_ready) begin
                if (!collecting) begin
                    allocated[wr_slot] <= 1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            complete <= '0;
        end
        else begin
            if (s_valid && s_ready) begin
                if (s_last) begin
                    complete[wr_slot] <= 1;
                end
            end
            if (ctx_valid && ctx_ready) begin
                if (ctx_cbmd == 0) begin
                    complete[dispatch_slot] <= 0;
                end
            end
            if (finish_request || (clear_valid && clear_ready)) begin
                if (dispatch_state == DISPATCH_PKG0) begin
                end
                else begin
                    complete[dispatch_slot] <= 0;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_slot <= 0;
        end
        else begin
            if (s_valid && s_ready) begin
                if (s_last) begin
                    wr_slot <= advance(wr_slot);
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dispatch_slot <= 0;
        end
        else begin
            if (ctx_valid && ctx_ready) begin
                if (ctx_cbmd == 0) begin
                    dispatch_slot <= advance(dispatch_slot);
                end
            end
            if (finish_request || (clear_valid && clear_ready)) begin
                if (dispatch_state == DISPATCH_PKG0) begin
                end
                else begin
                    dispatch_slot <= advance(dispatch_slot);
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat <= 0;
        end
        else begin
            if (s_valid && s_ready) begin
                if (s_last) begin
                    beat <= 0;
                end
                else begin
                    beat <= beat + 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            collecting <= 0;
        end
        else begin
            if (s_valid && s_ready) begin
                if (s_last) begin
                    collecting <= 0;
                end
                else begin
                    collecting <= 1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dispatch_state <= DISPATCH_CTX;
        end
        else begin
            if (ctx_valid && ctx_ready) begin
                if (ctx_cbmd == 0) begin
                end
                else begin
                    if (ctx_cbmd >= 6) begin
                        dispatch_state <= DISPATCH_CLEAR;
                    end
                    else begin
                        dispatch_state <= DISPATCH_PKG0;
                    end
                end
            end
            if (finish_request || (clear_valid && clear_ready)) begin
                if (dispatch_state == DISPATCH_PKG0) begin
                    dispatch_state <= DISPATCH_PKG1;
                end
                else begin
                    dispatch_state <= DISPATCH_CTX;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                if (!collecting) begin
                    cbmd_mem[wr_slot] <= s_cbmd;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                if (!collecting) begin
                    data_mem[wr_slot] <= s_has_data ? {768'b0, s_data} : 1024'b0;
                end
                else begin
                    if (s_has_data) begin
                        data_mem[wr_slot][int'(beat) * int'(STREAM_DATA_BITS) +: STREAM_DATA_BITS] <= s_data;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (load_snapshot) begin
                pkg_unit_id <= UNIT_ID_W'($unsigned(dispatch_slot));
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (load_snapshot) begin
                pkg_pkg_id <= dispatch_state == DISPATCH_PKG1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (load_snapshot) begin
                pkg_cbmd <= cbmd_mem[dispatch_slot];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (load_snapshot) begin
                pkg_region <= data_mem[dispatch_slot][767:0];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (load_snapshot) begin
                pkg_available_bytes <= received_bytes[dispatch_slot][6:0];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (load_snapshot) begin
                pkg_final <= complete[dispatch_slot];
            end
        end
    end
    // synthesis translate_off

    initial begin
        assert(UNIT_SLOTS > 0 && UNIT_SLOTS <= 2**UNIT_ID_W) else begin
            $fatal(1, "Invalid slots");
        end
    end
    always @(posedge clk) begin
        if (rst_n) begin
            assert(!$isunknown(dispatch_state)) else begin
                $error("Unknown decoder dispatch state");
            end
        end
        if (rst_n && s_valid && s_ready) begin : check_protocol
            int mode;
            mode = collecting ? int'(cbmd_mem[wr_slot]) : int'(s_cbmd);
            assert(s_sop == !collecting) else begin
                $error("Compressed SOP");
            end
            if (mode >= 6)
            begin
                assert(!s_has_data && s_last && !collecting) else begin
                    $error("Clear framing");
                end
            end
            else begin
                assert(s_has_data) else begin
                    $error("Missing compressed data");
                end
                assert(s_last == (int'(beat) == occupied_bytes(4'($unsigned(mode))) / int'(STREAM_BYTES) - 1))
                else begin
                    $error("Compressed LAST");
                end
            end
        end
    end
    // synthesis translate_on
endmodule : uddc_dec_split
`default_nettype wire
