// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module udc_enc_package
    #(
        parameter int unsigned UNIT_ID_W = 4
    )
    (
        input logic clk,
        input logic rst_n,
        input logic s_valid,
        output logic s_ready,
        input logic [UNIT_ID_W - 1:0] s_unit_id,
        input logic s_pkg_id,
        input logic [3:0] s_fmt,
        input logic s_decor,
        input logic [3:0][31:0] s_anchors,
        input logic [511:0] s_deltas,
        input logic [3:0] s_strategy,
        input logic [31:0][4:0] s_indexes,
        input logic [9:0] s_logical_bits,
        output logic m_valid,
        input logic m_ready,
        output logic [UNIT_ID_W - 1:0] m_unit_id,
        output logic m_pkg_id,
        output logic [3:0] m_fmt,
        output logic [6:0] m_size_bytes,
        output logic [543:0] m_bits,
        output logic m_error
    );

    function automatic int channels(input logic [3:0] f);
        case (f)
            1, 2, 3: begin
                return 1;
            end
            6, 7, 8, 12: begin
                return 2;
            end
            9, 13, 14: begin
                return 3;
            end
            4, 5, 10, 11: begin
                return 4;
            end
            default: begin
                return 0;
            end
        endcase
    endfunction

    function automatic int width_of(input logic [3:0] f, input int c);
        if (c >= channels(f)) begin
            return 0;
        end
        case (f)
            1, 6, 10: begin
                return 8;
            end
            2, 4, 7: begin
                return 16;
            end
            3, 5, 12, 14: begin
                return 32;
            end
            8: begin
                return c == 0 ? 24 : 8;
            end
            9: begin
                return c == 2 ? 10 : 11;
            end
            11: begin
                return c == 3 ? 2 : 10;
            end
            13: begin
                case (c)
                    0: begin
                        return 32;
                    end
                    1: begin
                        return 8;
                    end
                    default: begin
                        return 24;
                    end
                endcase
            end
            default: begin
                return 0;
            end
        endcase
    endfunction

    function automatic int samples(input logic [3:0] f, input int c);
        if (c >= channels(f)) begin
            return 0;
        end
        case (f)
            1: begin
                return 64;
            end
            2, 6: begin
                return 32;
            end
            3, 7, 8, 9, 10, 11: begin
                return 16;
            end
            4, 12, 13: begin
                return 8;
            end
            5: begin
                return 4;
            end
            14: begin
                return c == 0 ? 6 : 5;
            end
            default: begin
                return 0;
            end
        endcase
    endfunction

    function automatic int plane_base(input logic [3:0] f, input int c);
        int v;
        v = 0;
        for (int j = 0; j < 4; j++) begin
            if (j < c) begin
                v += width_of(f, j) * samples(f, j);
            end
        end
        return v;
    endfunction

    function automatic int pair_base(input logic [3:0] f, input int c);
        int v;
        v = 0;
        for (int j = 0; j < 4; j++) begin
            if (j < c) begin
                v += samples(f, j) / 2;
            end
        end
        return v;
    endfunction

    function automatic int index_bits(input int w);
        return w == 32 ? 5 : (w >= 16 ? 4 : 3);
    endfunction

    function automatic int decode_width(input int ix, input int w);
        int ib, terminal, dw;
        ib = index_bits(w);
        terminal = (1 << ib) - 1;
        dw = - 1;
        if (ix == 0) begin
            dw = 0;
        end
        else begin
            if (ix > 0 && ix < terminal) begin
                dw = ix + 1;
            end
            else begin
                if (ix == terminal && w > terminal) begin
                    dw = w;
                end
            end
        end
        if (dw > w) begin
            dw = - 1;
        end
        return dw;
    endfunction

    function automatic logic [31:0] mask_w(input int w);
        return w == 32 ? 32'hffffffff : ((32'h1 << w) - 1);
    endfunction

    function automatic logic [31:0] sample_at(
            input logic [511:0] v, input int pos, input int w);
        return 32'(v >> pos) & mask_w(w);
    endfunction

    function automatic void put_field(
            inout logic [543:0] dst, inout int cursor, input bit reverse,
            input int count, input logic [511:0] value, inout bit bad);
        int low_bit;
        low_bit = reverse ? cursor - count + 1 : cursor;
        if (count < 0 || count > 512 || low_bit < 0 || low_bit + count > 544)
        begin
            bad = 1;
        end
        else begin
            for (int b = 0; b < 512; b++)
            begin
                if (b < count) begin
                    dst[low_bit + b] = value[b];
                end
            end
            cursor += reverse ? - count : count;
        end
    endfunction
    logic [543:0] next_bits;
    logic [6:0] next_size;
    bit next_error;
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [543:0] compute_next_bits(
            input logic [3:0][31:0] arg_s_anchors,
            input logic arg_s_decor,
            input logic [511:0] arg_s_deltas,
            input logic [3:0] arg_s_fmt,
            input logic [31:0][4:0] arg_s_indexes,
            input logic [9:0] arg_s_logical_bits,
            input logic arg_s_pkg_id,
            input logic [3:0] arg_s_strategy);
        logic [543:0] value_next_bits;
        logic [6:0] value_next_size;
        bit value_next_error;
        begin : assemble
            int bytes, cursor, w, n, ib, pb, ixbase, count, offset, dw, ix, logical_count;
            logic [511:0] field_value;
            logic [31:0] delta;
            bytes = (int'(arg_s_logical_bits) + 7) / 8;
            value_next_bits = '0;
            value_next_size = 7'($unsigned(bytes));
            value_next_error = channels(arg_s_fmt) == 0 || bytes > 68 || bytes == 0;
            cursor = arg_s_pkg_id ? bytes * 8 - 1 : 0;
            w = 0;
            n = 0;
            ib = 0;
            pb = 0;
            ixbase = 0;
            count = 0;
            offset = 0;
            dw = 0;
            ix = 0;
            field_value = '0;
            delta = '0;
            logical_count = 7 + channels(arg_s_fmt);
            if (!value_next_error) begin
                put_field(value_next_bits, cursor, arg_s_pkg_id, 2, 512'b0, value_next_error);
                put_field(value_next_bits, cursor, arg_s_pkg_id, 4, 512'(arg_s_fmt), value_next_error);
                put_field(value_next_bits, cursor, arg_s_pkg_id, 1, 512'(arg_s_decor), value_next_error);
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt))
                    begin
                        put_field(value_next_bits, cursor, arg_s_pkg_id, 1, 512'(arg_s_strategy[c]), value_next_error);
                    end
                end
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt)) begin
                        w = width_of(arg_s_fmt, c);
                        n = samples(arg_s_fmt, c);
                        ib = index_bits(w);
                        ixbase = pair_base(arg_s_fmt, c);
                        count = arg_s_strategy[c] ? n / 2 : 1;
                        field_value = '0;
                        for (int p = 0; p < 32; p++) begin
                            if (p < count) begin
                                ix = int'(arg_s_indexes[ixbase + p]);
                                if (ix >= (1 << ib) || decode_width(ix, w) < 0) begin
                                    value_next_error = 1;
                                end
                                for (int bit_ix = 0; bit_ix < 5; bit_ix++)
                                begin
                                    if (bit_ix < ib) begin
                                        field_value[p * ib + bit_ix] = arg_s_indexes[ixbase + p][bit_ix];
                                    end
                                end
                            end
                        end
                        put_field(value_next_bits, cursor, arg_s_pkg_id, count * ib, field_value, value_next_error);
                        logical_count += count * ib;
                    end
                end
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt)) begin
                        w = width_of(arg_s_fmt, c);
                        put_field(value_next_bits, cursor, arg_s_pkg_id, w, 512'(arg_s_anchors[c]), value_next_error);
                        logical_count += w;
                    end
                end
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt)) begin
                        w = width_of(arg_s_fmt, c);
                        n = samples(arg_s_fmt, c);
                        pb = plane_base(arg_s_fmt, c);
                        ixbase = pair_base(arg_s_fmt, c);
                        field_value = '0;
                        offset = 0;
                        for (int k = 1; k < 64; k++) begin
                            if (k < n) begin
                                ix = int'(arg_s_indexes[ixbase + (arg_s_strategy[c] ? (k - 1) / 2 : 0)]);
                                dw = decode_width(ix, w);
                                delta = sample_at(arg_s_deltas, pb + k * w, w);
                                if (dw < 0 || offset + dw > 512) begin
                                    value_next_error = 1;
                                end
                                else begin
                                    for (int bit_ix = 0; bit_ix < 32; bit_ix++)
                                    begin
                                        if (bit_ix < dw) begin
                                            field_value[offset + bit_ix] = delta[bit_ix];
                                        end
                                    end
                                    offset += dw;
                                end
                            end
                        end
                        put_field(value_next_bits, cursor, arg_s_pkg_id, offset, field_value, value_next_error);
                        logical_count += offset;
                    end
                end
                if (logical_count != int'(arg_s_logical_bits)) begin
                    value_next_error = 1;
                end
            end
            if (value_next_error) begin
                value_next_bits = '0;
                value_next_size = '0;
            end
        end
        return value_next_bits;
    endfunction
    assign next_bits = compute_next_bits(s_anchors, s_decor, s_deltas, s_fmt, s_indexes, s_logical_bits, s_pkg_id, s_strategy);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [6:0] compute_next_size(
            input logic [3:0][31:0] arg_s_anchors,
            input logic arg_s_decor,
            input logic [511:0] arg_s_deltas,
            input logic [3:0] arg_s_fmt,
            input logic [31:0][4:0] arg_s_indexes,
            input logic [9:0] arg_s_logical_bits,
            input logic arg_s_pkg_id,
            input logic [3:0] arg_s_strategy);
        logic [543:0] value_next_bits;
        logic [6:0] value_next_size;
        bit value_next_error;
        begin : assemble
            int bytes, cursor, w, n, ib, pb, ixbase, count, offset, dw, ix, logical_count;
            logic [511:0] field_value;
            logic [31:0] delta;
            bytes = (int'(arg_s_logical_bits) + 7) / 8;
            value_next_bits = '0;
            value_next_size = 7'($unsigned(bytes));
            value_next_error = channels(arg_s_fmt) == 0 || bytes > 68 || bytes == 0;
            cursor = arg_s_pkg_id ? bytes * 8 - 1 : 0;
            w = 0;
            n = 0;
            ib = 0;
            pb = 0;
            ixbase = 0;
            count = 0;
            offset = 0;
            dw = 0;
            ix = 0;
            field_value = '0;
            delta = '0;
            logical_count = 7 + channels(arg_s_fmt);
            if (!value_next_error) begin
                put_field(value_next_bits, cursor, arg_s_pkg_id, 2, 512'b0, value_next_error);
                put_field(value_next_bits, cursor, arg_s_pkg_id, 4, 512'(arg_s_fmt), value_next_error);
                put_field(value_next_bits, cursor, arg_s_pkg_id, 1, 512'(arg_s_decor), value_next_error);
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt))
                    begin
                        put_field(value_next_bits, cursor, arg_s_pkg_id, 1, 512'(arg_s_strategy[c]), value_next_error);
                    end
                end
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt)) begin
                        w = width_of(arg_s_fmt, c);
                        n = samples(arg_s_fmt, c);
                        ib = index_bits(w);
                        ixbase = pair_base(arg_s_fmt, c);
                        count = arg_s_strategy[c] ? n / 2 : 1;
                        field_value = '0;
                        for (int p = 0; p < 32; p++) begin
                            if (p < count) begin
                                ix = int'(arg_s_indexes[ixbase + p]);
                                if (ix >= (1 << ib) || decode_width(ix, w) < 0) begin
                                    value_next_error = 1;
                                end
                                for (int bit_ix = 0; bit_ix < 5; bit_ix++)
                                begin
                                    if (bit_ix < ib) begin
                                        field_value[p * ib + bit_ix] = arg_s_indexes[ixbase + p][bit_ix];
                                    end
                                end
                            end
                        end
                        put_field(value_next_bits, cursor, arg_s_pkg_id, count * ib, field_value, value_next_error);
                        logical_count += count * ib;
                    end
                end
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt)) begin
                        w = width_of(arg_s_fmt, c);
                        put_field(value_next_bits, cursor, arg_s_pkg_id, w, 512'(arg_s_anchors[c]), value_next_error);
                        logical_count += w;
                    end
                end
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt)) begin
                        w = width_of(arg_s_fmt, c);
                        n = samples(arg_s_fmt, c);
                        pb = plane_base(arg_s_fmt, c);
                        ixbase = pair_base(arg_s_fmt, c);
                        field_value = '0;
                        offset = 0;
                        for (int k = 1; k < 64; k++) begin
                            if (k < n) begin
                                ix = int'(arg_s_indexes[ixbase + (arg_s_strategy[c] ? (k - 1) / 2 : 0)]);
                                dw = decode_width(ix, w);
                                delta = sample_at(arg_s_deltas, pb + k * w, w);
                                if (dw < 0 || offset + dw > 512) begin
                                    value_next_error = 1;
                                end
                                else begin
                                    for (int bit_ix = 0; bit_ix < 32; bit_ix++)
                                    begin
                                        if (bit_ix < dw) begin
                                            field_value[offset + bit_ix] = delta[bit_ix];
                                        end
                                    end
                                    offset += dw;
                                end
                            end
                        end
                        put_field(value_next_bits, cursor, arg_s_pkg_id, offset, field_value, value_next_error);
                        logical_count += offset;
                    end
                end
                if (logical_count != int'(arg_s_logical_bits)) begin
                    value_next_error = 1;
                end
            end
            if (value_next_error) begin
                value_next_bits = '0;
                value_next_size = '0;
            end
        end
        return value_next_size;
    endfunction
    assign next_size = compute_next_size(s_anchors, s_decor, s_deltas, s_fmt, s_indexes, s_logical_bits, s_pkg_id, s_strategy);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic bit compute_next_error(
            input logic [3:0][31:0] arg_s_anchors,
            input logic arg_s_decor,
            input logic [511:0] arg_s_deltas,
            input logic [3:0] arg_s_fmt,
            input logic [31:0][4:0] arg_s_indexes,
            input logic [9:0] arg_s_logical_bits,
            input logic arg_s_pkg_id,
            input logic [3:0] arg_s_strategy);
        logic [543:0] value_next_bits;
        logic [6:0] value_next_size;
        bit value_next_error;
        begin : assemble
            int bytes, cursor, w, n, ib, pb, ixbase, count, offset, dw, ix, logical_count;
            logic [511:0] field_value;
            logic [31:0] delta;
            bytes = (int'(arg_s_logical_bits) + 7) / 8;
            value_next_bits = '0;
            value_next_size = 7'($unsigned(bytes));
            value_next_error = channels(arg_s_fmt) == 0 || bytes > 68 || bytes == 0;
            cursor = arg_s_pkg_id ? bytes * 8 - 1 : 0;
            w = 0;
            n = 0;
            ib = 0;
            pb = 0;
            ixbase = 0;
            count = 0;
            offset = 0;
            dw = 0;
            ix = 0;
            field_value = '0;
            delta = '0;
            logical_count = 7 + channels(arg_s_fmt);
            if (!value_next_error) begin
                put_field(value_next_bits, cursor, arg_s_pkg_id, 2, 512'b0, value_next_error);
                put_field(value_next_bits, cursor, arg_s_pkg_id, 4, 512'(arg_s_fmt), value_next_error);
                put_field(value_next_bits, cursor, arg_s_pkg_id, 1, 512'(arg_s_decor), value_next_error);
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt))
                    begin
                        put_field(value_next_bits, cursor, arg_s_pkg_id, 1, 512'(arg_s_strategy[c]), value_next_error);
                    end
                end
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt)) begin
                        w = width_of(arg_s_fmt, c);
                        n = samples(arg_s_fmt, c);
                        ib = index_bits(w);
                        ixbase = pair_base(arg_s_fmt, c);
                        count = arg_s_strategy[c] ? n / 2 : 1;
                        field_value = '0;
                        for (int p = 0; p < 32; p++) begin
                            if (p < count) begin
                                ix = int'(arg_s_indexes[ixbase + p]);
                                if (ix >= (1 << ib) || decode_width(ix, w) < 0) begin
                                    value_next_error = 1;
                                end
                                for (int bit_ix = 0; bit_ix < 5; bit_ix++)
                                begin
                                    if (bit_ix < ib) begin
                                        field_value[p * ib + bit_ix] = arg_s_indexes[ixbase + p][bit_ix];
                                    end
                                end
                            end
                        end
                        put_field(value_next_bits, cursor, arg_s_pkg_id, count * ib, field_value, value_next_error);
                        logical_count += count * ib;
                    end
                end
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt)) begin
                        w = width_of(arg_s_fmt, c);
                        put_field(value_next_bits, cursor, arg_s_pkg_id, w, 512'(arg_s_anchors[c]), value_next_error);
                        logical_count += w;
                    end
                end
                for (int c = 0; c < 4; c++) begin
                    if (c < channels(arg_s_fmt)) begin
                        w = width_of(arg_s_fmt, c);
                        n = samples(arg_s_fmt, c);
                        pb = plane_base(arg_s_fmt, c);
                        ixbase = pair_base(arg_s_fmt, c);
                        field_value = '0;
                        offset = 0;
                        for (int k = 1; k < 64; k++) begin
                            if (k < n) begin
                                ix = int'(arg_s_indexes[ixbase + (arg_s_strategy[c] ? (k - 1) / 2 : 0)]);
                                dw = decode_width(ix, w);
                                delta = sample_at(arg_s_deltas, pb + k * w, w);
                                if (dw < 0 || offset + dw > 512) begin
                                    value_next_error = 1;
                                end
                                else begin
                                    for (int bit_ix = 0; bit_ix < 32; bit_ix++)
                                    begin
                                        if (bit_ix < dw) begin
                                            field_value[offset + bit_ix] = delta[bit_ix];
                                        end
                                    end
                                    offset += dw;
                                end
                            end
                        end
                        put_field(value_next_bits, cursor, arg_s_pkg_id, offset, field_value, value_next_error);
                        logical_count += offset;
                    end
                end
                if (logical_count != int'(arg_s_logical_bits)) begin
                    value_next_error = 1;
                end
            end
            if (value_next_error) begin
                value_next_bits = '0;
                value_next_size = '0;
            end
        end
        return value_next_error;
    endfunction
    assign next_error = compute_next_error(s_anchors, s_decor, s_deltas, s_fmt, s_indexes, s_logical_bits, s_pkg_id, s_strategy);
    assign s_ready = !m_valid || m_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid <= 1'b0;
        end
        else begin
            if (s_ready) begin
                m_valid <= s_valid;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid) begin
                    m_unit_id <= s_unit_id;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid) begin
                    m_pkg_id <= s_pkg_id;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid) begin
                    m_fmt <= s_fmt;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid) begin
                    m_bits <= next_bits;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid) begin
                    m_size_bytes <= next_size;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid) begin
                    m_error <= next_error;
                end
            end
        end
    end
endmodule : udc_enc_package
`default_nettype wire
