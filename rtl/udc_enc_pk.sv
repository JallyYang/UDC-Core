// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module udc_enc_pk
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
        input logic [3:0] ctx_fmt,
        input logic [6:0] ctx_limit_bytes,
        input logic ctx_clear_hit,
        input logic [3:0] ctx_clear_index,
        input logic [1023:0] ctx_raw,
        input logic pkg_valid,
        output logic pkg_ready,
        input logic [UNIT_ID_W - 1:0] pkg_unit_id,
        input logic pkg_pkg_id,
        input logic [3:0] pkg_fmt,
        input logic [6:0] pkg_size_bytes,
        input logic [543:0] pkg_bits,
        input logic pkg_error,
        output logic m_valid,
        input logic m_ready,
        output logic [255:0] m_data,
        output logic m_sop,
        output logic m_last,
        output logic m_has_data,
        output logic [3:0] m_cbmd,
        output logic retire_valid,
        output logic [UNIT_ID_W - 1:0] retire_unit_id
    );
    logic [UNIT_SLOTS - 1:0] live;
    logic [UNIT_SLOTS - 1:0] clear_hit;
    logic [1:0] done[0:UNIT_SLOTS - 1];
    logic [1:0] errors[0:UNIT_SLOTS - 1];
    logic [1023:0] raw_mem[0:UNIT_SLOTS - 1];
    logic [543:0] bits0[0:UNIT_SLOTS - 1];
    logic [543:0] bits1[0:UNIT_SLOTS - 1];
    logic [6:0] size0[0:UNIT_SLOTS - 1];
    logic [6:0] size1[0:UNIT_SLOTS - 1];
    logic [6:0] limits[0:UNIT_SLOTS - 1];
    logic [3:0] fmts[0:UNIT_SLOTS - 1];
    logic [3:0] clear_ix[0:UNIT_SLOTS - 1];
    logic [UNIT_ID_W - 1:0] order_mem[0:UNIT_SLOTS - 1];
    integer head;
    integer tail;
    integer count;
    localparam int unsigned STREAM_DATA_BITS = 256;
    localparam int unsigned STREAM_BYTES = STREAM_DATA_BITS / 8;
    localparam int unsigned UNIT_BEATS = 1024 / STREAM_DATA_BITS;
    localparam int unsigned BEAT_WIDTH = $clog2(UNIT_BEATS);
    localparam logic [BEAT_WIDTH - 1:0] LAST_UNIT_BEAT = BEAT_WIDTH'(UNIT_BEATS - 1);
    logic [BEAT_WIDTH - 1:0] beat;
    logic [UNIT_ID_W - 1:0] head_id;
    logic [1023:0] packet;
    logic [3:0] selected_cbmd;
    integer byte_count;
    logic available;
    logic push;
    logic pop;

    function automatic int advance(input int slot);
        return slot == int'(UNIT_SLOTS) - 1 ? 0 : slot + 1;
    endfunction
    assign head_id = count != 0 ? order_mem[head] : '0;
    assign ctx_ready = rst_n && count < int'(UNIT_SLOTS) && int'(ctx_unit_id) < int'(UNIT_SLOTS) &&
        !live[ctx_unit_id];
    assign pkg_ready = rst_n && int'(pkg_unit_id) < int'(UNIT_SLOTS) &&
        live[pkg_unit_id] && !done[pkg_unit_id][pkg_pkg_id];
    assign push = ctx_valid && ctx_ready;
    assign pop = m_valid && m_ready && m_last;
    assign retire_valid = pop;
    assign retire_unit_id = head_id;
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [1023:0] compute_packet(
        input logic [543:0] arg_bits0[0:UNIT_SLOTS - 1],
        input logic [543:0] arg_bits1[0:UNIT_SLOTS - 1],
        input logic [UNIT_SLOTS - 1:0] arg_clear_hit,
        input logic [3:0] arg_clear_ix[0:UNIT_SLOTS - 1],
        input integer arg_count,
        input logic [1:0] arg_done[0:UNIT_SLOTS - 1],
        input logic [1:0] arg_errors[0:UNIT_SLOTS - 1],
        input logic [UNIT_ID_W - 1:0] arg_head_id,
        input logic [6:0] arg_limits[0:UNIT_SLOTS - 1],
        input logic [1023:0] arg_raw_mem[0:UNIT_SLOTS - 1],
        input logic [6:0] arg_size0[0:UNIT_SLOTS - 1],
        input logic [6:0] arg_size1[0:UNIT_SLOTS - 1]
    );
        logic [1023:0] value_packet;
        logic [3:0] value_selected_cbmd;
        logic value_available;
        integer value_byte_count;
        begin : form_packet
            int a;
            int b;
            int total;
            int occupied;
            int start1;
            logic [31:0] fill_word;
            a = 0;
            b = 0;
            total = 0;
            occupied = 128;
            start1 = 0;
            fill_word = 32'hdeadbeef;
            value_packet = '0;
            value_selected_cbmd = 0;
            value_available = 0;
            value_byte_count = 128;
            if (arg_count != 0) begin
                value_packet = arg_raw_mem[arg_head_id];
                if (arg_clear_hit[arg_head_id]) begin
                    value_available = 1;
                    value_selected_cbmd = 4'd6 + arg_clear_ix[arg_head_id];
                    value_packet = '0;
                    value_byte_count = 0;
                end
                else begin
                    if (arg_limits[arg_head_id] == 0) begin
                        value_available = 1;
                    end
                    else begin
                        if ( & arg_done[arg_head_id]) begin
                            value_available = 1;
                            a = int'(arg_size0[arg_head_id]);
                            b = int'(arg_size1[arg_head_id]);
                            total = a + b;
                            if (arg_errors[arg_head_id] == 0 && a > 0 && b > 0 &&
                                a <= int'(arg_limits[arg_head_id]) && b <= int'(arg_limits[arg_head_id]) &&
                                a <= 68 && b <= 68 && total <= 96) begin
                                if (total <= 32) begin
                                    value_selected_cbmd = 1;
                                    occupied = 32;
                                end
                                else begin
                                    if (total <= 64) begin
                                        occupied = 64;
                                        if (a <= 32 && b <= 32) begin
                                            value_selected_cbmd = 2;
                                        end
                                        else begin
                                            if (a < 32) begin
                                                value_selected_cbmd = 3;
                                            end
                                            else begin
                                                value_selected_cbmd = 4;
                                            end
                                        end
                                    end
                                    else begin
                                        value_selected_cbmd = 5;
                                        occupied = 96;
                                    end
                                end
                                value_packet = '0;
                                value_byte_count = occupied;
                                start1 = occupied - b;
                                for (int j = 0; j < 128; j++) begin
                                    if (j < a) begin
                                        value_packet[j * 8 +: 8] = 8'(arg_bits0[arg_head_id] >> (j * 8));
                                    end
                                    else begin
                                        if (j >= start1 && j < occupied)
                                        begin
                                            value_packet[j * 8 +: 8] = 8'(arg_bits1[arg_head_id] >> ((j - start1) * 8));
                                        end
                                        else begin
                                            if (j < start1)
                                            begin
                                                value_packet[j * 8 +: 8] = 8'(fill_word >> (((j - a) % 4) * 8));
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return value_packet;
    endfunction
    assign packet = compute_packet(bits0, bits1, clear_hit, clear_ix, count, done, errors, head_id, limits, raw_mem, size0, size1);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [3:0] compute_selected_cbmd(
        input logic [543:0] arg_bits0[0:UNIT_SLOTS - 1],
        input logic [543:0] arg_bits1[0:UNIT_SLOTS - 1],
        input logic [UNIT_SLOTS - 1:0] arg_clear_hit,
        input logic [3:0] arg_clear_ix[0:UNIT_SLOTS - 1],
        input integer arg_count,
        input logic [1:0] arg_done[0:UNIT_SLOTS - 1],
        input logic [1:0] arg_errors[0:UNIT_SLOTS - 1],
        input logic [UNIT_ID_W - 1:0] arg_head_id,
        input logic [6:0] arg_limits[0:UNIT_SLOTS - 1],
        input logic [1023:0] arg_raw_mem[0:UNIT_SLOTS - 1],
        input logic [6:0] arg_size0[0:UNIT_SLOTS - 1],
        input logic [6:0] arg_size1[0:UNIT_SLOTS - 1]
    );
        logic [1023:0] value_packet;
        logic [3:0] value_selected_cbmd;
        logic value_available;
        integer value_byte_count;
        begin : form_packet
            int a;
            int b;
            int total;
            int occupied;
            int start1;
            logic [31:0] fill_word;
            a = 0;
            b = 0;
            total = 0;
            occupied = 128;
            start1 = 0;
            fill_word = 32'hdeadbeef;
            value_packet = '0;
            value_selected_cbmd = 0;
            value_available = 0;
            value_byte_count = 128;
            if (arg_count != 0) begin
                value_packet = arg_raw_mem[arg_head_id];
                if (arg_clear_hit[arg_head_id]) begin
                    value_available = 1;
                    value_selected_cbmd = 4'd6 + arg_clear_ix[arg_head_id];
                    value_packet = '0;
                    value_byte_count = 0;
                end
                else begin
                    if (arg_limits[arg_head_id] == 0) begin
                        value_available = 1;
                    end
                    else begin
                        if ( & arg_done[arg_head_id]) begin
                            value_available = 1;
                            a = int'(arg_size0[arg_head_id]);
                            b = int'(arg_size1[arg_head_id]);
                            total = a + b;
                            if (arg_errors[arg_head_id] == 0 && a > 0 && b > 0 &&
                                a <= int'(arg_limits[arg_head_id]) && b <= int'(arg_limits[arg_head_id]) &&
                                a <= 68 && b <= 68 && total <= 96) begin
                                if (total <= 32) begin
                                    value_selected_cbmd = 1;
                                    occupied = 32;
                                end
                                else begin
                                    if (total <= 64) begin
                                        occupied = 64;
                                        if (a <= 32 && b <= 32) begin
                                            value_selected_cbmd = 2;
                                        end
                                        else begin
                                            if (a < 32) begin
                                                value_selected_cbmd = 3;
                                            end
                                            else begin
                                                value_selected_cbmd = 4;
                                            end
                                        end
                                    end
                                    else begin
                                        value_selected_cbmd = 5;
                                        occupied = 96;
                                    end
                                end
                                value_packet = '0;
                                value_byte_count = occupied;
                                start1 = occupied - b;
                                for (int j = 0; j < 128; j++) begin
                                    if (j < a) begin
                                        value_packet[j * 8 +: 8] = 8'(arg_bits0[arg_head_id] >> (j * 8));
                                    end
                                    else begin
                                        if (j >= start1 && j < occupied)
                                        begin
                                            value_packet[j * 8 +: 8] = 8'(arg_bits1[arg_head_id] >> ((j - start1) * 8));
                                        end
                                        else begin
                                            if (j < start1)
                                            begin
                                                value_packet[j * 8 +: 8] = 8'(fill_word >> (((j - a) % 4) * 8));
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return value_selected_cbmd;
    endfunction
    assign selected_cbmd = compute_selected_cbmd(bits0, bits1, clear_hit, clear_ix, count, done, errors, head_id, limits, raw_mem, size0, size1);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic compute_available(
        input logic [543:0] arg_bits0[0:UNIT_SLOTS - 1],
        input logic [543:0] arg_bits1[0:UNIT_SLOTS - 1],
        input logic [UNIT_SLOTS - 1:0] arg_clear_hit,
        input logic [3:0] arg_clear_ix[0:UNIT_SLOTS - 1],
        input integer arg_count,
        input logic [1:0] arg_done[0:UNIT_SLOTS - 1],
        input logic [1:0] arg_errors[0:UNIT_SLOTS - 1],
        input logic [UNIT_ID_W - 1:0] arg_head_id,
        input logic [6:0] arg_limits[0:UNIT_SLOTS - 1],
        input logic [1023:0] arg_raw_mem[0:UNIT_SLOTS - 1],
        input logic [6:0] arg_size0[0:UNIT_SLOTS - 1],
        input logic [6:0] arg_size1[0:UNIT_SLOTS - 1]
    );
        logic [1023:0] value_packet;
        logic [3:0] value_selected_cbmd;
        logic value_available;
        integer value_byte_count;
        begin : form_packet
            int a;
            int b;
            int total;
            int occupied;
            int start1;
            logic [31:0] fill_word;
            a = 0;
            b = 0;
            total = 0;
            occupied = 128;
            start1 = 0;
            fill_word = 32'hdeadbeef;
            value_packet = '0;
            value_selected_cbmd = 0;
            value_available = 0;
            value_byte_count = 128;
            if (arg_count != 0) begin
                value_packet = arg_raw_mem[arg_head_id];
                if (arg_clear_hit[arg_head_id]) begin
                    value_available = 1;
                    value_selected_cbmd = 4'd6 + arg_clear_ix[arg_head_id];
                    value_packet = '0;
                    value_byte_count = 0;
                end
                else begin
                    if (arg_limits[arg_head_id] == 0) begin
                        value_available = 1;
                    end
                    else begin
                        if ( & arg_done[arg_head_id]) begin
                            value_available = 1;
                            a = int'(arg_size0[arg_head_id]);
                            b = int'(arg_size1[arg_head_id]);
                            total = a + b;
                            if (arg_errors[arg_head_id] == 0 && a > 0 && b > 0 &&
                                a <= int'(arg_limits[arg_head_id]) && b <= int'(arg_limits[arg_head_id]) &&
                                a <= 68 && b <= 68 && total <= 96) begin
                                if (total <= 32) begin
                                    value_selected_cbmd = 1;
                                    occupied = 32;
                                end
                                else begin
                                    if (total <= 64) begin
                                        occupied = 64;
                                        if (a <= 32 && b <= 32) begin
                                            value_selected_cbmd = 2;
                                        end
                                        else begin
                                            if (a < 32) begin
                                                value_selected_cbmd = 3;
                                            end
                                            else begin
                                                value_selected_cbmd = 4;
                                            end
                                        end
                                    end
                                    else begin
                                        value_selected_cbmd = 5;
                                        occupied = 96;
                                    end
                                end
                                value_packet = '0;
                                value_byte_count = occupied;
                                start1 = occupied - b;
                                for (int j = 0; j < 128; j++) begin
                                    if (j < a) begin
                                        value_packet[j * 8 +: 8] = 8'(arg_bits0[arg_head_id] >> (j * 8));
                                    end
                                    else begin
                                        if (j >= start1 && j < occupied)
                                        begin
                                            value_packet[j * 8 +: 8] = 8'(arg_bits1[arg_head_id] >> ((j - start1) * 8));
                                        end
                                        else begin
                                            if (j < start1)
                                            begin
                                                value_packet[j * 8 +: 8] = 8'(fill_word >> (((j - a) % 4) * 8));
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return value_available;
    endfunction
    assign available = compute_available(bits0, bits1, clear_hit, clear_ix, count, done, errors, head_id, limits, raw_mem, size0, size1);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic integer compute_byte_count(
        input logic [543:0] arg_bits0[0:UNIT_SLOTS - 1],
        input logic [543:0] arg_bits1[0:UNIT_SLOTS - 1],
        input logic [UNIT_SLOTS - 1:0] arg_clear_hit,
        input logic [3:0] arg_clear_ix[0:UNIT_SLOTS - 1],
        input integer arg_count,
        input logic [1:0] arg_done[0:UNIT_SLOTS - 1],
        input logic [1:0] arg_errors[0:UNIT_SLOTS - 1],
        input logic [UNIT_ID_W - 1:0] arg_head_id,
        input logic [6:0] arg_limits[0:UNIT_SLOTS - 1],
        input logic [1023:0] arg_raw_mem[0:UNIT_SLOTS - 1],
        input logic [6:0] arg_size0[0:UNIT_SLOTS - 1],
        input logic [6:0] arg_size1[0:UNIT_SLOTS - 1]
    );
        logic [1023:0] value_packet;
        logic [3:0] value_selected_cbmd;
        logic value_available;
        integer value_byte_count;
        begin : form_packet
            int a;
            int b;
            int total;
            int occupied;
            int start1;
            logic [31:0] fill_word;
            a = 0;
            b = 0;
            total = 0;
            occupied = 128;
            start1 = 0;
            fill_word = 32'hdeadbeef;
            value_packet = '0;
            value_selected_cbmd = 0;
            value_available = 0;
            value_byte_count = 128;
            if (arg_count != 0) begin
                value_packet = arg_raw_mem[arg_head_id];
                if (arg_clear_hit[arg_head_id]) begin
                    value_available = 1;
                    value_selected_cbmd = 4'd6 + arg_clear_ix[arg_head_id];
                    value_packet = '0;
                    value_byte_count = 0;
                end
                else begin
                    if (arg_limits[arg_head_id] == 0) begin
                        value_available = 1;
                    end
                    else begin
                        if ( & arg_done[arg_head_id]) begin
                            value_available = 1;
                            a = int'(arg_size0[arg_head_id]);
                            b = int'(arg_size1[arg_head_id]);
                            total = a + b;
                            if (arg_errors[arg_head_id] == 0 && a > 0 && b > 0 &&
                                a <= int'(arg_limits[arg_head_id]) && b <= int'(arg_limits[arg_head_id]) &&
                                a <= 68 && b <= 68 && total <= 96) begin
                                if (total <= 32) begin
                                    value_selected_cbmd = 1;
                                    occupied = 32;
                                end
                                else begin
                                    if (total <= 64) begin
                                        occupied = 64;
                                        if (a <= 32 && b <= 32) begin
                                            value_selected_cbmd = 2;
                                        end
                                        else begin
                                            if (a < 32) begin
                                                value_selected_cbmd = 3;
                                            end
                                            else begin
                                                value_selected_cbmd = 4;
                                            end
                                        end
                                    end
                                    else begin
                                        value_selected_cbmd = 5;
                                        occupied = 96;
                                    end
                                end
                                value_packet = '0;
                                value_byte_count = occupied;
                                start1 = occupied - b;
                                for (int j = 0; j < 128; j++) begin
                                    if (j < a) begin
                                        value_packet[j * 8 +: 8] = 8'(arg_bits0[arg_head_id] >> (j * 8));
                                    end
                                    else begin
                                        if (j >= start1 && j < occupied)
                                        begin
                                            value_packet[j * 8 +: 8] = 8'(arg_bits1[arg_head_id] >> ((j - start1) * 8));
                                        end
                                        else begin
                                            if (j < start1)
                                            begin
                                                value_packet[j * 8 +: 8] = 8'(fill_word >> (((j - a) % 4) * 8));
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return value_byte_count;
    endfunction
    assign byte_count = compute_byte_count(bits0, bits1, clear_hit, clear_ix, count, done, errors, head_id, limits, raw_mem, size0, size1);
    assign m_valid = rst_n && available;
    assign m_data = packet[int'(beat) * int'(STREAM_DATA_BITS) +: STREAM_DATA_BITS];
    assign m_sop = beat == 0;
    assign m_has_data = selected_cbmd < 6;
    assign m_last = selected_cbmd >= 6 || int'(beat) == byte_count / int'(STREAM_BYTES) - 1;
    assign m_cbmd = beat == 0 ? selected_cbmd : 4'b0;

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
            clear_hit <= '0;
        end
        else begin
            if (push) begin
                clear_hit[ctx_unit_id] <= ctx_clear_hit;
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
                errors[pkg_unit_id][pkg_pkg_id] <= pkg_error || pkg_fmt != fmts[pkg_unit_id];
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
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (push) begin
                fmts[ctx_unit_id] <= ctx_fmt;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (push) begin
                limits[ctx_unit_id] <= ctx_limit_bytes;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (push) begin
                clear_ix[ctx_unit_id] <= ctx_clear_index;
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
                    bits1[pkg_unit_id] <= pkg_bits;
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
                end
                else begin
                    bits0[pkg_unit_id] <= pkg_bits;
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
    // synthesis translate_off

    initial begin
        assert(UNIT_SLOTS > 0 && UNIT_SLOTS <= 2**UNIT_ID_W) else begin
            $fatal(1, "Invalid slots");
        end
    end
    // synthesis translate_on
endmodule : udc_enc_pk
`default_nettype wire
