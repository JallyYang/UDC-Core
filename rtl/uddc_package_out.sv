// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module uddc_package_out
    #(
        parameter int unsigned UNIT_ID_W = 4,
        parameter int unsigned UNIT_SLOTS = 8
    )
    (
        input logic clk,
        input logic rst_n,
        input logic ctx_valid,
        output logic ctx_ready,
        input logic [UNIT_ID_W - 1:0] ctx_unit_id,
        input logic [3:0] ctx_cbmd,
        input logic [1023:0] ctx_raw,
        input logic pkg_valid,
        output logic pkg_ready,
        input logic [UNIT_ID_W - 1:0] pkg_unit_id,
        input logic pkg_pkg_id,
        input logic [3:0] pkg_fmt,
        input logic [511:0] pkg_raw,
        input logic [6:0] pkg_size_bytes,
        input logic pkg_error,
        input logic clear_valid,
        output logic clear_ready,
        input logic [UNIT_ID_W - 1:0] clear_unit_id,
        input logic [1023:0] clear_raw,
        output logic m_valid,
        input logic m_ready,
        output logic [255:0] m_data,
        output logic m_sop,
        output logic m_last,
        output logic m_error,
        output logic retire_valid,
        output logic [UNIT_ID_W - 1:0] retire_unit_id
    );

    function automatic bit valid_sizes(input logic [3:0] cbmd, input int a, b);
        int total;
        // int operands avoid a 7-bit package-size sum wrapping at 128 bytes.
        total = a + b;
        if (a <= 0 || b <= 0) begin
            return 0;
        end
        case (cbmd)
            1: begin
                return total <= 32;
            end
            2: begin
                return total > 32 && total <= 64 && a <= 32 && b <= 32;
            end
            3: begin
                return total > 32 && total <= 64 && a < 32 && b > 32;
            end
            4: begin
                return total > 32 && total <= 64 && b < 32 && a > 32;
            end
            5: begin
                return total > 64 && total <= 96;
            end
            default: begin
                return 0;
            end
        endcase
    endfunction
    logic [UNIT_SLOTS - 1:0] live, clear_done;
    logic [1:0] done[0:UNIT_SLOTS - 1], errors[0:UNIT_SLOTS - 1];
    logic [1023:0] raw_mem[0:UNIT_SLOTS - 1];
    logic [3:0] mode_mem[0:UNIT_SLOTS - 1], fmt0[0:UNIT_SLOTS - 1], fmt1[0:UNIT_SLOTS - 1];
    logic [6:0] size0[0:UNIT_SLOTS - 1], size1[0:UNIT_SLOTS - 1];
    logic [UNIT_ID_W - 1:0] order_mem[0:UNIT_SLOTS - 1];
    integer head, tail, count;
    localparam int unsigned STREAM_DATA_BITS = 256;
    localparam int unsigned STREAM_BYTES = STREAM_DATA_BITS / 8;
    localparam int unsigned UNIT_BEATS = 1024 / STREAM_DATA_BITS;
    localparam int unsigned BEAT_WIDTH = $clog2(UNIT_BEATS);
    localparam logic [BEAT_WIDTH - 1:0] LAST_UNIT_BEAT = BEAT_WIDTH'(UNIT_BEATS - 1);
    logic [BEAT_WIDTH - 1:0] beat;
    logic [UNIT_ID_W - 1:0] head_id;
    logic available, unit_error, push, pop;

    function automatic int advance(input int slot);
        return slot == int'(UNIT_SLOTS) - 1 ? 0 : slot + 1;
    endfunction
    assign head_id = count != 0 ? order_mem[head] : '0;
    assign ctx_ready = rst_n && count < int'(UNIT_SLOTS) && int'(ctx_unit_id) < int'(UNIT_SLOTS) &&
        !live[ctx_unit_id];
    assign pkg_ready = rst_n && int'(pkg_unit_id) < int'(UNIT_SLOTS) &&
        live[pkg_unit_id] && !done[pkg_unit_id][pkg_pkg_id];
    assign clear_ready = rst_n && int'(clear_unit_id) < int'(UNIT_SLOTS) &&
        live[clear_unit_id] && !clear_done[clear_unit_id];
    assign push = ctx_valid && ctx_ready;
    assign pop = m_valid && m_ready && m_last;
    assign retire_valid = pop;
    assign retire_unit_id = head_id;
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic compute_available(
            input logic [UNIT_SLOTS - 1:0] arg_clear_done,
            input integer arg_count,
            input logic [1:0] arg_done[0:UNIT_SLOTS - 1],
            input logic [1:0] arg_errors[0:UNIT_SLOTS - 1],
            input logic [3:0] arg_fmt0[0:UNIT_SLOTS - 1],
            input logic [3:0] arg_fmt1[0:UNIT_SLOTS - 1],
            input logic [UNIT_ID_W - 1:0] arg_head_id,
            input logic [3:0] arg_mode_mem[0:UNIT_SLOTS - 1],
            input logic [6:0] arg_size0[0:UNIT_SLOTS - 1],
            input logic [6:0] arg_size1[0:UNIT_SLOTS - 1]);
        logic value_available;
        logic value_unit_error;
        begin
            value_available = 0;
            value_unit_error = 0;
            if (arg_count != 0) begin
                if (arg_mode_mem[arg_head_id] == 0) begin
                    value_available = 1;
                end
                else begin
                    if (arg_mode_mem[arg_head_id] >= 6) begin
                        value_available = arg_clear_done[arg_head_id];
                    end
                    else begin
                        value_available = & arg_done[arg_head_id];
                        if (value_available) begin
                            value_unit_error = ( | arg_errors[arg_head_id]) || arg_fmt0[arg_head_id] != arg_fmt1[arg_head_id] ||
                                !valid_sizes(arg_mode_mem[arg_head_id], int'(arg_size0[arg_head_id]), int'(arg_size1[arg_head_id]));
                        end
                    end
                end
            end
        end
        return value_available;
    endfunction
    assign available = compute_available(clear_done, count, done, errors, fmt0, fmt1, head_id, mode_mem, size0, size1);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic compute_unit_error(
            input logic [UNIT_SLOTS - 1:0] arg_clear_done,
            input integer arg_count,
            input logic [1:0] arg_done[0:UNIT_SLOTS - 1],
            input logic [1:0] arg_errors[0:UNIT_SLOTS - 1],
            input logic [3:0] arg_fmt0[0:UNIT_SLOTS - 1],
            input logic [3:0] arg_fmt1[0:UNIT_SLOTS - 1],
            input logic [UNIT_ID_W - 1:0] arg_head_id,
            input logic [3:0] arg_mode_mem[0:UNIT_SLOTS - 1],
            input logic [6:0] arg_size0[0:UNIT_SLOTS - 1],
            input logic [6:0] arg_size1[0:UNIT_SLOTS - 1]);
        logic value_available;
        logic value_unit_error;
        begin
            value_available = 0;
            value_unit_error = 0;
            if (arg_count != 0) begin
                if (arg_mode_mem[arg_head_id] == 0) begin
                    value_available = 1;
                end
                else begin
                    if (arg_mode_mem[arg_head_id] >= 6) begin
                        value_available = arg_clear_done[arg_head_id];
                    end
                    else begin
                        value_available = & arg_done[arg_head_id];
                        if (value_available) begin
                            value_unit_error = ( | arg_errors[arg_head_id]) || arg_fmt0[arg_head_id] != arg_fmt1[arg_head_id] ||
                                !valid_sizes(arg_mode_mem[arg_head_id], int'(arg_size0[arg_head_id]), int'(arg_size1[arg_head_id]));
                        end
                    end
                end
            end
        end
        return value_unit_error;
    endfunction
    assign unit_error = compute_unit_error(clear_done, count, done, errors, fmt0, fmt1, head_id, mode_mem, size0, size1);
    assign m_valid = rst_n && available;
    assign m_sop = beat == 0;
    assign m_last = beat == LAST_UNIT_BEAT;
    assign m_error = unit_error;
    assign m_data = unit_error || count == 0 ? '0 : raw_mem[head_id][int'(beat) * int'(STREAM_DATA_BITS) +: STREAM_DATA_BITS];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            live <= '0;
        end
        else begin
            if (push) begin
                live[ctx_unit_id] <= 1;
            end
            if (m_valid && m_ready) begin
                if (m_last) begin
                    live[head_id] <= 0;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_done <= '0;
        end
        else begin
            if (push) begin
                clear_done[ctx_unit_id] <= 0;
            end
            if (clear_valid && clear_ready) begin
                clear_done[clear_unit_id] <= 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= 0;
        end
        else begin
            if (m_valid && m_ready) begin
                if (m_last) begin
                    head <= advance(head);
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tail <= 0;
        end
        else begin
            if (push) begin
                tail <= advance(tail);
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
        end
        else begin
            case ({push, pop})
                2'b10: begin
                    count <= count + 1;
                end
                2'b01: begin
                    count <= count - 1;
                end
                default: begin
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat <= 0;
        end
        else begin
            if (m_valid && m_ready) begin
                if (m_last) begin
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
            done <= '{default: '0};
        end
        else begin
            if (push) begin
                done[ctx_unit_id] <= 0;
            end
            if (pkg_valid && pkg_ready) begin
                done[pkg_unit_id][pkg_pkg_id] <= 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            errors <= '{default: '0};
        end
        else begin
            if (push) begin
                errors[ctx_unit_id] <= 0;
            end
            if (pkg_valid && pkg_ready) begin
                errors[pkg_unit_id][pkg_pkg_id] <= pkg_error;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (push) begin
                raw_mem[ctx_unit_id] <= ctx_raw;
            end
            if (pkg_valid && pkg_ready) begin
                if (pkg_pkg_id) begin
                    raw_mem[pkg_unit_id][1023:512] <= pkg_raw;
                end
                else begin
                    raw_mem[pkg_unit_id][511:0] <= pkg_raw;
                end
            end
            if (clear_valid && clear_ready) begin
                raw_mem[clear_unit_id] <= clear_raw;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (push) begin
                mode_mem[ctx_unit_id] <= ctx_cbmd;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (push) begin
                order_mem[tail] <= ctx_unit_id;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (pkg_valid && pkg_ready) begin
                if (pkg_pkg_id) begin
                    size1[pkg_unit_id] <= pkg_size_bytes;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (pkg_valid && pkg_ready) begin
                if (pkg_pkg_id) begin
                    fmt1[pkg_unit_id] <= pkg_fmt;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (pkg_valid && pkg_ready) begin
                if (pkg_pkg_id) begin
                end
                else begin
                    size0[pkg_unit_id] <= pkg_size_bytes;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (pkg_valid && pkg_ready) begin
                if (pkg_pkg_id) begin
                end
                else begin
                    fmt0[pkg_unit_id] <= pkg_fmt;
                end
            end
        end
    end
    // synthesis translate_off

    initial begin
        assert(UNIT_SLOTS > 0 && UNIT_SLOTS <= 2**UNIT_ID_W) else begin
            $fatal(1, "Invalid slots");
        end
    end
    // synthesis translate_on
endmodule : uddc_package_out
`default_nettype wire
