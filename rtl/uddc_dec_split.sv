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
        input logic pkg_done,
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
    logic [UNIT_SLOTS-1:0] allocated, complete, started;
    logic [1023:0] data_mem [0:UNIT_SLOTS-1];
    logic [3:0] cbmd_mem [0:UNIT_SLOTS-1];
    logic [7:0] received_bytes [0:UNIT_SLOTS-1];
    integer wr_slot, dispatch_slot;
    localparam int STREAM_BYTES = 32;
    logic [1:0] beat;
    logic collecting;
    localparam logic [1:0] DISPATCH_CTX = 0, DISPATCH_PKG0 = 1,
                           DISPATCH_PKG1 = 2, DISPATCH_CLEAR = 3;
    logic [1:0] dispatch_state;
    logic input_accepted, context_accepted, package_request_accepted, package_parse_finished, clear_request_accepted;
    logic bypass_ctx, load_snapshot, snapshot_pkg_id;
    logic [1023:0] snapshot_data;
    logic [7:0] snapshot_bytes, offered_bytes;
    logic snapshot_complete;
    logic [3:0] snapshot_cbmd;

    function automatic int advance(input int slot);
        return slot == int'(UNIT_SLOTS)-1 ? 0 : slot+1;
    endfunction

    assign s_ready = rst_n && (collecting || !allocated[wr_slot]);
    assign input_accepted = s_valid && s_ready;
    // A compressed first beat can allocate its output context and parsing
    // snapshot together. Buffered units still dispatch strictly in order.
    assign bypass_ctx = input_accepted && !collecting && wr_slot == dispatch_slot &&
                        !started[dispatch_slot] && s_cbmd >= 1 && s_cbmd <= 5;
    assign ctx_valid = rst_n && dispatch_state == DISPATCH_CTX &&
                       (bypass_ctx || (started[dispatch_slot] &&
                        (cbmd_mem[dispatch_slot] != 0 || complete[dispatch_slot])));
    assign ctx_unit_id = UNIT_ID_W'(dispatch_slot);
    assign ctx_cbmd = bypass_ctx ? s_cbmd : cbmd_mem[dispatch_slot];
    assign ctx_raw = ctx_cbmd == 0 ? data_mem[dispatch_slot] : '0;
    assign context_accepted = ctx_valid && ctx_ready;
    assign package_request_accepted = pkg_valid && pkg_ready;
    // The parser acknowledges a complete parse, not just the final sector.
    // This permits pkg0 to retire before the occupied region is complete.
    assign package_parse_finished = package_request_accepted && pkg_done;
    assign clear_valid = rst_n && dispatch_state == DISPATCH_CLEAR;
    assign clear_unit_id = UNIT_ID_W'(dispatch_slot);
    assign clear_index = cbmd_mem[dispatch_slot] - 4'd6;
    assign clear_request_accepted = clear_valid && clear_ready;

    always_comb begin
        snapshot_data = data_mem[dispatch_slot];
        snapshot_bytes = received_bytes[dispatch_slot];
        snapshot_complete = complete[dispatch_slot];
        snapshot_cbmd = cbmd_mem[dispatch_slot];
        // Forward only accepted beats into the next registered snapshot.
        // The active request remains immutable while pkg_ready is low.
        if (input_accepted && wr_slot == dispatch_slot) begin
            if (!collecting) begin
                snapshot_data = s_has_data ? {768'b0, s_data} : '0;
                snapshot_cbmd = s_cbmd;
            end else if (s_has_data) begin
                snapshot_data[int'(beat)*256 +: 256] = s_data;
            end
            snapshot_bytes = s_has_data ? 8'((int'(beat)+1)*32) : 0;
            snapshot_complete = s_last;
        end
        snapshot_pkg_id = dispatch_state == DISPATCH_PKG1 ||
                          (dispatch_state == DISPATCH_PKG0 && package_parse_finished);
        load_snapshot = 0;
        if (rst_n && (!pkg_valid || pkg_ready)) begin
            if (context_accepted && ctx_cbmd >= 1 && ctx_cbmd <= 5)
                load_snapshot = 1;
            else if (dispatch_state == DISPATCH_PKG0) begin
                if (package_parse_finished)
                    load_snapshot = snapshot_complete;
                else
                    load_snapshot = snapshot_bytes > offered_bytes;
            end else if (dispatch_state == DISPATCH_PKG1 && !package_parse_finished)
                load_snapshot = snapshot_complete &&
                                (!pkg_valid || !pkg_pkg_id);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            allocated <= '0;
            complete <= '0;
            started <= '0;
            received_bytes <= '{default:'0};
            wr_slot <= 0;
            dispatch_slot <= 0;
            dispatch_state <= DISPATCH_CTX;
            beat <= 0;
            collecting <= 0;
            pkg_valid <= 0;
            offered_bytes <= 0;
        end else begin
            if (retire_valid) allocated[retire_unit_id] <= 0;
            if (input_accepted) begin
                if (!collecting) begin
                    allocated[wr_slot] <= 1;
                    started[wr_slot] <= 1;
                    cbmd_mem[wr_slot] <= s_cbmd;
                    data_mem[wr_slot] <= s_has_data ? {768'b0,s_data} : '0;
                end else if (s_has_data) begin
                    data_mem[wr_slot][int'(beat)*256 +: 256] <= s_data;
                end
                received_bytes[wr_slot] <= s_has_data ? 8'((int'(beat)+1)*32) : 0;
                if (s_last) begin
                    complete[wr_slot] <= 1;
                    wr_slot <= advance(wr_slot);
                    beat <= 0;
                end else beat <= beat+1'b1;
                collecting <= !s_last;
            end
            if (context_accepted) begin
                started[dispatch_slot] <= 0;
                offered_bytes <= 0;
                if (ctx_cbmd == 0) begin
                    complete[dispatch_slot] <= 0;
                    dispatch_slot <= advance(dispatch_slot);
                end else if (ctx_cbmd >= 6) dispatch_state <= DISPATCH_CLEAR;
                else dispatch_state <= DISPATCH_PKG0;
            end
            if (package_parse_finished) begin
                if (dispatch_state == DISPATCH_PKG0)
                    dispatch_state <= DISPATCH_PKG1;
                else begin
                    dispatch_state <= DISPATCH_CTX;
                    complete[dispatch_slot] <= 0;
                    dispatch_slot <= advance(dispatch_slot);
                end
            end
            if (clear_request_accepted) begin
                complete[dispatch_slot] <= 0;
                dispatch_state <= DISPATCH_CTX;
                dispatch_slot <= advance(dispatch_slot);
            end
            if (load_snapshot) begin
                pkg_valid <= 1;
                pkg_unit_id <= UNIT_ID_W'(dispatch_slot);
                pkg_pkg_id <= snapshot_pkg_id;
                pkg_cbmd <= snapshot_cbmd;
                pkg_region <= snapshot_data[767:0];
                pkg_available_bytes <= snapshot_bytes[6:0];
                pkg_final <= snapshot_complete;
                offered_bytes <= snapshot_bytes;
            end else if (package_request_accepted) pkg_valid <= 0;
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
