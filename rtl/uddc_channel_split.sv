// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module uddc_channel_split
    #(
        parameter int unsigned UNIT_ID_W = 4
    )
    (
        input logic clk,
        input logic rst_n,
        input logic s_valid,
        output logic s_ready,
        output logic s_done,
        input logic [UNIT_ID_W - 1:0] s_unit_id,
        input logic s_pkg_id,
        input logic [3:0] s_cbmd,
        input logic [767:0] s_region,
        input logic [6:0] s_available_bytes,
        input logic s_final,
        output logic m_valid,
        input logic m_ready,
        output logic [UNIT_ID_W - 1:0] m_unit_id,
        output logic m_pkg_id,
        output logic [3:0] m_fmt,
        output logic m_decor,
        output logic [3:0][31:0] m_anchors,
        output logic [511:0] m_deltas,
        output logic [6:0] m_size_bytes,
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

    function automatic bit can_decor(input logic [3:0] f);
        return f == 4 || f == 5 || f == 9 || f == 10 || f == 11;
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

    function automatic logic [511:0] set_sample(
            input logic [511:0] v, input int pos, input int w, input logic [31:0] x);
        logic [511:0] r;
        // Only the low w bits are stored: modulo 2**w wrap is intentional.
        r = v;
        for (int b = 0; b < 32; b++)
        begin
            if (b < w && pos + b >= 0 && pos + b < 512) begin
                r[pos + b] = x[b];
            end
        end
        return r;
    endfunction

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

    function automatic void take_field(
            input logic [767:0] src, input int bound, input bit reverse,
            inout int cursor, input int count, output logic [767:0] value,
            inout bit bad);
        int low_bit;
        value = '0;
        low_bit = reverse ? cursor - count + 1 : cursor;
        if (!bad) begin
            if (count < 0 || count > 768 || low_bit < 0 || low_bit + count > bound)
            begin
                bad = 1;
            end
            else begin
                for (int b = 0; b < 768; b++)
                begin
                    if (b < count) begin
                        value[b] = src[low_bit + b];
                    end
                end
                cursor += reverse ? - count : count;
            end
        end
    endfunction
    logic [3:0] next_fmt;
    logic next_decor;
    logic [3:0][31:0] next_anchors;
    logic [511:0] next_deltas;
    logic [6:0] next_size;
    bit next_error;
    typedef struct packed {
        logic [3:0] fmt;
        logic decor;
        logic [3:0][31:0] anchors;
        logic [511:0] deltas;
        logic [6:0] size_bytes;
        logic error;
    } parsed_t;
    parsed_t parsed;
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic parsed_t decode_snapshot(
            input logic [3:0] arg_s_cbmd,
            input logic arg_s_pkg_id,
            input logic [767:0] arg_s_region,
            input logic [6:0] arg_available_bytes);
        logic [3:0] value_next_fmt;
        logic value_next_decor;
        logic [3:0][31:0] value_next_anchors;
        logic [511:0] value_next_deltas;
        logic [6:0] value_next_size;
        bit value_next_error;
        begin : parse
            int bound, cursor, w, n, ib, count, ix, offset, total_dw, pb, dw, used, low_cursor;
            int delta_width[0:3][0:62];
            logic [3:0] strategy;
            logic [767:0] field_value;
            logic [31:0] value;
            bound = occupied_bytes(arg_s_cbmd) * 8;
            cursor = arg_s_pkg_id ? bound - 1 : 0;
            value_next_fmt = 0;
            value_next_decor = 0;
            value_next_anchors = '0;
            value_next_deltas = '0;
            value_next_size = 0;
            value_next_error = arg_s_cbmd < 1 || arg_s_cbmd > 5;
            w = 0;
            n = 0;
            ib = 0;
            count = 0;
            ix = 0;
            offset = 0;
            total_dw = 0;
            pb = 0;
            dw = 0;
            used = 0;
            low_cursor = 0;
            strategy = 0;
            field_value = 0;
            value = 0;
            for (int c = 0; c < 4; c++)
            begin
                for (int k = 0; k < 63; k++) begin
                    delta_width[c][k] = 0;
                end
            end
            take_field(arg_s_region, (int'(arg_available_bytes) * 8 < bound ? int'(arg_available_bytes) * 8 : bound), arg_s_pkg_id, cursor, 2, field_value, value_next_error);
            if (field_value[1:0] != 0) begin
                value_next_error = 1;
            end
            take_field(arg_s_region, (int'(arg_available_bytes) * 8 < bound ? int'(arg_available_bytes) * 8 : bound), arg_s_pkg_id, cursor, 4, field_value, value_next_error);
            value_next_fmt = field_value[3:0];
            if (channels(value_next_fmt) == 0) begin
                value_next_error = 1;
            end
            take_field(arg_s_region, (int'(arg_available_bytes) * 8 < bound ? int'(arg_available_bytes) * 8 : bound), arg_s_pkg_id, cursor, 1, field_value, value_next_error);
            value_next_decor = field_value[0] && can_decor(value_next_fmt);
            for (int c = 0; c < 4; c++) begin
                if (!value_next_error && c < channels(value_next_fmt)) begin
                    take_field(arg_s_region, (int'(arg_available_bytes) * 8 < bound ? int'(arg_available_bytes) * 8 : bound), arg_s_pkg_id, cursor, 1, field_value, value_next_error);
                    strategy[c] = field_value[0];
                end
            end
            for (int c = 0; c < 4; c++) begin
                if (!value_next_error && c < channels(value_next_fmt)) begin
                    w = width_of(value_next_fmt, c);
                    n = samples(value_next_fmt, c);
                    ib = index_bits(w);
                    count = strategy[c] ? n / 2 : 1;
                    take_field(arg_s_region, (int'(arg_available_bytes) * 8 < bound ? int'(arg_available_bytes) * 8 : bound), arg_s_pkg_id, cursor, count * ib, field_value, value_next_error);
                    for (int k = 0; k < 63; k++) begin
                        if (k < n - 1 && !value_next_error) begin
                            offset = (strategy[c] ? k / 2 : 0) * ib;
                            ix = int'((field_value >> offset) & 768'($unsigned((1 << ib) - 1)));
                            dw = decode_width(ix, w);
                            if (dw < 0) begin
                                value_next_error = 1;
                            end
                            else begin
                                delta_width[c][k] = dw;
                            end
                        end
                    end
                end
            end
            for (int c = 0; c < 4; c++) begin
                if (!value_next_error && c < channels(value_next_fmt)) begin
                    w = width_of(value_next_fmt, c);
                    take_field(arg_s_region, (int'(arg_available_bytes) * 8 < bound ? int'(arg_available_bytes) * 8 : bound), arg_s_pkg_id, cursor, w, field_value, value_next_error);
                    value_next_anchors[c] = field_value[31:0] & mask_w(w);
                end
            end
            for (int c = 0; c < 4; c++) begin
                if (!value_next_error && c < channels(value_next_fmt)) begin
                    w = width_of(value_next_fmt, c);
                    n = samples(value_next_fmt, c);
                    pb = plane_base(value_next_fmt, c);
                    total_dw = 0;
                    for (int k = 0; k < 63; k++) begin
                        if (k < n - 1) begin
                            total_dw += delta_width[c][k];
                        end
                    end
                    take_field(arg_s_region, (int'(arg_available_bytes) * 8 < bound ? int'(arg_available_bytes) * 8 : bound), arg_s_pkg_id, cursor, total_dw, field_value, value_next_error);
                    offset = 0;
                    for (int k = 0; k < 63; k++) begin
                        if (k < n - 1 && !value_next_error) begin
                            dw = delta_width[c][k];
                            value = 0;
                            if (dw > 0) begin
                                value = 32'(field_value >> offset) & mask_w(dw);
                                value = $unsigned($signed(value << (32 - dw)) >>> (32 - dw));
                            end
                            value_next_deltas = set_sample(value_next_deltas, pb + (k + 1) * w, w, value);
                            offset += dw;
                        end
                    end
                end
            end
            used = arg_s_pkg_id ? bound - 1 - cursor : cursor;
            value_next_size = 7'($unsigned((used + 7) / 8));
            low_cursor = arg_s_pkg_id ? bound - int'(value_next_size) * 8 : int'(value_next_size) * 8;
            if (used <= 0 || used > bound || low_cursor < 0 || low_cursor > bound) begin
                value_next_error = 1;
            end
            if (value_next_error) begin
                value_next_fmt = 0;
                value_next_decor = 0;
                value_next_anchors = 0;
                value_next_deltas = 0;
                value_next_size = 0;
            end
        end
        return {value_next_fmt, value_next_decor, value_next_anchors,
                value_next_deltas, value_next_size, value_next_error};
    endfunction
    assign parsed = decode_snapshot(s_cbmd, s_pkg_id, s_region, s_available_bytes);
    assign next_fmt = parsed.fmt;
    assign next_decor = parsed.decor;
    assign next_anchors = parsed.anchors;
    assign next_deltas = parsed.deltas;
    assign next_size = parsed.size_bytes;
    assign next_error = parsed.error;
    // Each accepted snapshot either completes the package or requests more
    // bytes. The dispatcher advances immediately on completion, so no global
    // result_sent state or final-sector cleanup transaction is needed.
    logic emit_result;
    assign emit_result = !next_error || s_final;
    assign s_done = emit_result;
    assign s_ready = !m_valid || m_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid <= 1'b0;
        end
        else begin
            if (s_ready) begin
                m_valid <= s_valid && emit_result;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid && emit_result) begin
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
                if (s_valid && emit_result) begin
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
                if (s_valid && emit_result) begin
                    m_fmt <= next_fmt;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid && emit_result) begin
                    m_decor <= next_decor;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid && emit_result) begin
                    m_anchors <= next_anchors;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid && emit_result) begin
                    m_deltas <= next_deltas;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_ready) begin
                if (s_valid && emit_result) begin
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
                if (s_valid && emit_result) begin
                    m_error <= next_error;
                end
            end
        end
    end
endmodule : uddc_channel_split
`default_nettype wire
