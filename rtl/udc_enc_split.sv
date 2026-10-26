// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module udc_enc_split
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
        input logic [3:0] s_udc_format,
        input logic [6:0] s_package_size_limit,
        output logic clear_req_valid,
        input logic clear_req_ready,
        output logic [UNIT_ID_W - 1:0] clear_req_unit_id,
        output logic clear_req_sop,
        output logic clear_req_last,
        output logic [255:0] clear_req_data,
        input logic clear_rsp_valid,
        output logic clear_rsp_ready,
        input logic [UNIT_ID_W - 1:0] clear_rsp_unit_id,
        input logic clear_rsp_hit,
        input logic [3:0] clear_rsp_index,
        output logic ctx_valid,
        input logic ctx_ready,
        output logic [UNIT_ID_W - 1:0] ctx_unit_id,
        output logic [3:0] ctx_fmt,
        output logic [6:0] ctx_limit_bytes,
        output logic ctx_clear_hit,
        output logic [3:0] ctx_clear_index,
        output logic [1023:0] ctx_raw,
        output logic pkg_valid,
        input logic pkg_ready,
        output logic [UNIT_ID_W - 1:0] pkg_unit_id,
        output logic pkg_pkg_id,
        output logic [3:0] pkg_fmt,
        output logic [511:0] pkg_raw,
        input logic retire_valid,
        input logic [UNIT_ID_W - 1:0] retire_unit_id
    );
    logic [UNIT_SLOTS - 1:0] allocated, complete, clear_done, clear_hits;
    logic [1023:0] raw_mem[0:UNIT_SLOTS - 1];
    logic [3:0] fmt_mem[0:UNIT_SLOTS - 1], clear_index_mem[0:UNIT_SLOTS - 1];
    logic [6:0] limit_mem[0:UNIT_SLOTS - 1];
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
    // Encoding 3 is unreachable from reset; retain existing behavior and flag it.
    logic [1:0] dispatch_state;

    function automatic int advance(input int slot);
        return slot == int'(UNIT_SLOTS) - 1 ? 0 : slot + 1;
    endfunction
    assign s_ready = rst_n && (collecting || !allocated[wr_slot]) &&
        (!clear_req_valid || clear_req_ready);
    assign clear_rsp_ready = rst_n;
    assign ctx_valid = rst_n && complete[dispatch_slot] && clear_done[dispatch_slot] &&
        dispatch_state == DISPATCH_CTX;
    assign ctx_unit_id = UNIT_ID_W'($unsigned(dispatch_slot));
    assign ctx_fmt = fmt_mem[dispatch_slot];
    assign ctx_limit_bytes = limit_mem[dispatch_slot];
    assign ctx_clear_hit = clear_hits[dispatch_slot];
    assign ctx_clear_index = clear_index_mem[dispatch_slot];
    assign ctx_raw = raw_mem[dispatch_slot];
    assign pkg_valid = rst_n && dispatch_state != DISPATCH_CTX;
    assign pkg_unit_id = UNIT_ID_W'($unsigned(dispatch_slot));
    assign pkg_pkg_id = dispatch_state == DISPATCH_PKG1;
    assign pkg_fmt = fmt_mem[dispatch_slot];
    assign pkg_raw = dispatch_state == DISPATCH_PKG1 ? raw_mem[dispatch_slot][1023:512] :
        raw_mem[dispatch_slot][511:0];

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
                if (beat == LAST_UNIT_BEAT) begin
                    complete[wr_slot] <= 1;
                end
            end
            if (ctx_valid && ctx_ready) begin
                if (ctx_clear_hit || ctx_limit_bytes == 0) begin
                    complete[dispatch_slot] <= 0;
                end
            end
            if (pkg_valid && pkg_ready) begin
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
            clear_done <= '0;
        end
        else begin
            if (s_valid && s_ready) begin
                if (!collecting) begin
                    clear_done[wr_slot] <= 0;
                end
            end
            if (clear_rsp_valid && clear_rsp_ready) begin
                clear_done[clear_rsp_unit_id] <= 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_hits <= '0;
        end
        else begin
            if (s_valid && s_ready) begin
                if (!collecting) begin
                    clear_hits[wr_slot] <= 0;
                end
            end
            if (clear_rsp_valid && clear_rsp_ready) begin
                clear_hits[clear_rsp_unit_id] <= clear_rsp_hit;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_slot <= 0;
        end
        else begin
            if (s_valid && s_ready) begin
                if (beat == LAST_UNIT_BEAT) begin
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
                if (ctx_clear_hit || ctx_limit_bytes == 0) begin
                    dispatch_slot <= advance(dispatch_slot);
                end
            end
            if (pkg_valid && pkg_ready) begin
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
                if (beat == LAST_UNIT_BEAT) begin
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
                if (beat == LAST_UNIT_BEAT) begin
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
                if (ctx_clear_hit || ctx_limit_bytes == 0) begin
                end
                else begin
                    dispatch_state <= DISPATCH_PKG0;
                end
            end
            if (pkg_valid && pkg_ready) begin
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
            clear_req_valid <= 0;
        end
        else begin
            if (clear_req_valid && clear_req_ready) begin
                clear_req_valid <= 0;
            end
            if (s_valid && s_ready) begin
                clear_req_valid <= 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                raw_mem[wr_slot][int'(beat) * int'(STREAM_DATA_BITS) +: STREAM_DATA_BITS] <= s_data;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                clear_req_unit_id <= UNIT_ID_W'($unsigned(wr_slot));
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                clear_req_sop <= s_sop;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                clear_req_last <= s_last;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                clear_req_data <= s_data;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                if (!collecting) begin
                    fmt_mem[wr_slot] <= s_udc_format >= 1 && s_udc_format <= 14 ? s_udc_format : 4'ha;
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
                    limit_mem[wr_slot] <= s_package_size_limit > 68 ? 7'd68 : s_package_size_limit;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (clear_rsp_valid && clear_rsp_ready) begin
                clear_index_mem[clear_rsp_unit_id] <= clear_rsp_hit ? clear_rsp_index : 4'b0;
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
            assert(dispatch_state == DISPATCH_CTX || dispatch_state == DISPATCH_PKG0 ||
                dispatch_state == DISPATCH_PKG1) else begin
                $error("Illegal encoder dispatch state");
            end
        end
        if (rst_n && s_valid && s_ready) begin
            assert(s_sop == (beat == 0) && s_last == (beat == LAST_UNIT_BEAT)) else begin
                $error("Raw input framing");
            end
        end
    end
    // synthesis translate_on
endmodule : udc_enc_split
`default_nettype wire
