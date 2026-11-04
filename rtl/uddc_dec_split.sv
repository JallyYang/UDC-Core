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
        input logic pkg_response_valid,
        input logic pkg_streaming,
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
    logic [UNIT_SLOTS-1:0] allocated;
    logic [UNIT_SLOTS-1:0] complete;
    logic [UNIT_SLOTS-1:0] started;
    logic [1023:0] data_mem [0:UNIT_SLOTS-1];
    logic [3:0] cbmd_mem [0:UNIT_SLOTS-1];
    logic [7:0] received_bytes [0:UNIT_SLOTS-1];
    integer wr_slot;
    integer dispatch_slot;
    localparam int STREAM_BYTES = 32;
    logic [1:0] beat;
    logic collecting;
    localparam logic [1:0] DISPATCH_CTX = 0;
    localparam logic [1:0] DISPATCH_PKG0 = 1;
    localparam logic [1:0] DISPATCH_PKG1 = 2;
    localparam logic [1:0] DISPATCH_CLEAR = 3;
    logic [1:0] dispatch_state;
    logic [1:0] next_dispatch_state;
    logic input_accepted;
    logic context_accepted;
    logic package_request_accepted;
    logic package_dispatch_finished;
    logic parse_waiting;
    logic clear_request_accepted;
    logic bypass_ctx;
    logic load_snapshot;
    logic snapshot_queue_ready;
    logic snapshot_enqueued;
    logic snapshot_pkg_id;
    logic [1023:0] snapshot_data;
    logic [7:0] snapshot_bytes;
    logic [7:0] offered_bytes;
    logic snapshot_complete;
    logic [3:0] snapshot_cbmd;

    function automatic int advance(input int slot);
        return slot == int'(UNIT_SLOTS)-1 ? 0 : slot+1;
    endfunction

    // Only non-streaming mode waits for a response before another request.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) parse_waiting <= 1'b0;
        else if (pkg_response_valid) parse_waiting <= 1'b0;
        else if (package_request_accepted) parse_waiting <= 1'b1;
    end

    // FSM part 1: current-state register.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dispatch_state <= DISPATCH_CTX;
        end else begin
            dispatch_state <= next_dispatch_state;
        end
    end

    // FSM part 2: combinational next-state calculation.
    always_comb begin
        next_dispatch_state = dispatch_state;
        case (dispatch_state)
            DISPATCH_CTX: begin
                if (context_accepted && ctx_cbmd != 0) begin
                    if (ctx_cbmd >= 6) next_dispatch_state = DISPATCH_CLEAR;
                    else if (pkg_streaming && snapshot_enqueued && snapshot_complete)
                        next_dispatch_state = DISPATCH_PKG1;
                    else next_dispatch_state = DISPATCH_PKG0;
                end
            end
            DISPATCH_PKG0: begin
                if (package_dispatch_finished)
                    next_dispatch_state = DISPATCH_PKG1;
            end
            DISPATCH_PKG1: begin
                if (package_dispatch_finished)
                    next_dispatch_state = DISPATCH_CTX;
            end
            DISPATCH_CLEAR: begin
                if (clear_request_accepted)
                    next_dispatch_state = DISPATCH_CTX;
            end
            default: begin
                next_dispatch_state = dispatch_state;
            end
        endcase
    end

    // FSM part 3: combinational outputs, one target per process.
    assign s_ready = collecting || !allocated[wr_slot] ||
        (retire_valid && int'(retire_unit_id) == wr_slot);
    assign input_accepted = s_valid && s_ready;
    // A compressed first beat can allocate its output context and parsing
    // snapshot together. Buffered units still dispatch strictly in order.
    assign bypass_ctx = input_accepted && !collecting && wr_slot == dispatch_slot &&
                        !started[dispatch_slot] && s_cbmd >= 1 && s_cbmd <= 5;
    always_comb begin
        ctx_valid = dispatch_state == DISPATCH_CTX &&
                       (bypass_ctx || (started[dispatch_slot] &&
                        (cbmd_mem[dispatch_slot] != 0 || complete[dispatch_slot])));
    end
    assign ctx_unit_id = UNIT_ID_W'(dispatch_slot);
    assign ctx_cbmd = bypass_ctx ? s_cbmd : cbmd_mem[dispatch_slot];
    assign ctx_raw = ctx_cbmd == 0 ? data_mem[dispatch_slot] : '0;
    assign context_accepted = ctx_valid && ctx_ready;
    assign package_request_accepted = pkg_valid && pkg_ready;
    // Streaming production closes when the final snapshot enters the local
    // queue. The parser may consume that immutable snapshot later.
    // Non-streaming dispatch still waits for the corresponding response.
    assign snapshot_enqueued = load_snapshot && snapshot_queue_ready;
    assign package_dispatch_finished = pkg_streaming ?
        snapshot_enqueued && snapshot_complete : pkg_response_valid && pkg_done;
    always_comb begin
        clear_valid = dispatch_state == DISPATCH_CLEAR;
    end
    assign clear_unit_id = UNIT_ID_W'(dispatch_slot);
    assign clear_index = cbmd_mem[dispatch_slot] - 4'd6;
    assign clear_request_accepted = clear_valid && clear_ready;

    always_comb begin
        load_snapshot = 1'b0;
        if (snapshot_queue_ready) begin
            if (context_accepted && ctx_cbmd >= 1 && ctx_cbmd <= 5) begin
                load_snapshot = 1'b1;
            end else if (pkg_streaming) begin
                if (dispatch_state == DISPATCH_PKG0)
                    load_snapshot = snapshot_bytes > offered_bytes;
                else if (dispatch_state == DISPATCH_PKG1)
                    load_snapshot = snapshot_complete;
            end else if ((!pkg_valid || pkg_ready) &&
                         ((!parse_waiting && !pkg_valid) || pkg_response_valid)) begin
                // Response-driven mode must not queue speculative requests.
                if (dispatch_state == DISPATCH_PKG0) begin
                    if (package_dispatch_finished) load_snapshot = snapshot_complete;
                    else load_snapshot = snapshot_bytes > offered_bytes;
                end else if (dispatch_state == DISPATCH_PKG1 && !package_dispatch_finished)
                    load_snapshot = snapshot_complete && (!pkg_valid || !pkg_pkg_id);
            end
        end
    end

    always_comb begin
        snapshot_bytes = received_bytes[dispatch_slot];
        if (input_accepted && wr_slot == dispatch_slot) begin
            snapshot_bytes = s_has_data ? 8'((int'(beat)+1)*32) : 0;
        end
    end

    always_comb begin
        snapshot_cbmd = cbmd_mem[dispatch_slot];
        if (input_accepted && wr_slot == dispatch_slot) begin
            if (!collecting) begin
                snapshot_cbmd = s_cbmd;
            end
        end
    end

    always_comb begin
        snapshot_complete = complete[dispatch_slot];
        if (input_accepted && wr_slot == dispatch_slot) begin
            snapshot_complete = s_last;
        end
    end

    always_comb begin
        snapshot_data = data_mem[dispatch_slot];
        if (input_accepted && wr_slot == dispatch_slot) begin
            if (!collecting) begin
                snapshot_data = s_has_data ? {768'b0, s_data} : '0;
            end else begin
                if (s_has_data) begin
                    snapshot_data[int'(beat)*256 +: 256] = s_data;
                end
            end
        end
    end

    always_comb begin
        snapshot_pkg_id = dispatch_state == DISPATCH_PKG1 ||
                          (!pkg_streaming && dispatch_state == DISPATCH_PKG0 && package_dispatch_finished);
    end

    for (genvar slot_index = 0; slot_index < UNIT_SLOTS; slot_index++) begin : input_completion
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) complete[slot_index] <= 1'b0;
            else if ((context_accepted && ctx_cbmd == 0 && dispatch_slot == slot_index) ||
                     (package_dispatch_finished && dispatch_state == DISPATCH_PKG1 && dispatch_slot == slot_index) ||
                     (clear_request_accepted && dispatch_slot == slot_index))
                complete[slot_index] <= 1'b0;
            else if (input_accepted && s_last && wr_slot == slot_index)
                complete[slot_index] <= 1'b1;
        end
    end

    // Output uses its own cache, so a retiring input slot can accept a new
    // first beat on the same edge. Reallocation takes explicit priority.
    for (genvar slot_index = 0; slot_index < UNIT_SLOTS; slot_index++) begin : input_slot_allocation
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) allocated[slot_index] <= 1'b0;
            else if (input_accepted && !collecting && wr_slot == slot_index)
                allocated[slot_index] <= 1'b1;
            else if (retire_valid && int'(retire_unit_id) == slot_index)
                allocated[slot_index] <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat <= 0;
        end else begin
            if (input_accepted) begin
                if (s_last) begin
                    beat <= 0;
                end else begin
                    beat <= beat+1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end else begin
            if (input_accepted) begin
                if (!collecting) begin
                    cbmd_mem[wr_slot] <= s_cbmd;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            collecting <= 0;
        end else begin
            if (input_accepted) begin
                collecting <= !s_last;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end else begin
            if (input_accepted) begin
                if (!collecting) begin
                    data_mem[wr_slot] <= s_has_data ? {768'b0,s_data} : '0;
                end else begin
                    if (s_has_data) begin
                        data_mem[wr_slot][int'(beat)*256 +: 256] <= s_data;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) dispatch_slot <= 0;
        else if ((context_accepted && ctx_cbmd == 0) ||
                 (package_dispatch_finished && dispatch_state == DISPATCH_PKG1) ||
                 clear_request_accepted)
            dispatch_slot <= advance(dispatch_slot);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) offered_bytes <= '0;
        else if (snapshot_enqueued) offered_bytes <= snapshot_bytes;
        else if (context_accepted) offered_bytes <= '0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            received_bytes <= '{default:'0};
        end else begin
            if (input_accepted) begin
                received_bytes[wr_slot] <= s_has_data ? 8'((int'(beat)+1)*32) : 0;
            end
        end
    end

    // Update each slot independently. A context accepted on its first input
    // beat is already delivered, so clearing takes explicit priority.
    for (genvar slot_index = 0; slot_index < UNIT_SLOTS; slot_index++) begin : context_pending_flag
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                started[slot_index] <= 1'b0;
            end else if (context_accepted && dispatch_slot == slot_index) begin
                started[slot_index] <= 1'b0;
            end else if (input_accepted && !collecting && wr_slot == slot_index) begin
                started[slot_index] <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_slot <= 0;
        end else begin
            if (input_accepted) begin
                if (s_last) begin
                    wr_slot <= advance(wr_slot);
                end
            end
        end
    end
    // Payload order (MSB to LSB) follows the named port concatenations.
    de_rs_reg #(.NORST(1), .PLD_W(UNIT_ID_W+1+4+768+7+1)) u_snapshot_slice (
        .aclk_i(clk), .aresetn_i(rst_n),
        .valid_i(load_snapshot), .ready_o(snapshot_queue_ready),
        .ready_i(pkg_ready), .valid_o(pkg_valid),
        .payload_i({UNIT_ID_W'(dispatch_slot), snapshot_pkg_id, snapshot_cbmd, snapshot_data[767:0], snapshot_bytes[6:0], snapshot_complete}),
        .payload_o({pkg_unit_id, pkg_pkg_id, pkg_cbmd, pkg_region, pkg_available_bytes, pkg_final})
    );
endmodule : uddc_dec_split
