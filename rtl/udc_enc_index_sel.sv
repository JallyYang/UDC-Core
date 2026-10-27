// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module udc_enc_index_sel
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
        output logic m_valid,
        input logic m_ready,
        output logic [UNIT_ID_W - 1:0] m_unit_id,
        output logic m_pkg_id,
        output logic [3:0] m_fmt,
        output logic m_decor,
        output logic [3:0][31:0] m_anchors,
        output logic [511:0] m_deltas,
        output logic [3:0] m_strategy,
        output logic [31:0][4:0] m_indexes,
        output logic [9:0] m_logical_bits
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

    function automatic int width_of(
        input logic [3:0] f,
        input int c
    );
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

    function automatic int samples(
        input logic [3:0] f,
        input int c
    );
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

    function automatic int plane_base(
        input logic [3:0] f,
        input int c
    );
        int v;
        v = 0;
        for (int j = 0; j < 4; j++) begin
            if (j < c) begin
                v += width_of(f, j) * samples(f, j);
            end
        end
        return v;
    endfunction

    function automatic int pair_base(
        input logic [3:0] f,
        input int c
    );
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

    function automatic int decode_width(
        input int ix,
        input int w
    );
        int ib;
        int terminal;
        int dw;
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
        input logic [511:0] v,
        input int pos,
        input int w
    );
        return 32'(v >> pos) & mask_w(w);
    endfunction

    function automatic int min_index(
        input logic [31:0] x,
        input int w
    );
        logic signed [31:0] sx;
        logic signed [31:0] narrowed;
        int answer;
        int dw;
        // Interpret the already wrapped w-bit residual as signed two's complement.
        sx = $signed(x << (32 - w)) >>> (32 - w);
        answer = - 1;
        for (int ix = 0; ix < 32; ix++) begin
            dw = decode_width(ix, w);
            narrowed = 0;
            if (dw > 0) begin
                narrowed = (sx <<< (32 - dw)) >>> (32 - dw);
            end
            if (answer < 0 && dw >= 0 &&
                ((dw == 0 && sx == 0) || (dw > 0 && narrowed == sx))) begin
                answer = ix;
            end
        end
        return answer;
    endfunction
    logic [3:0] next_strategy;
    logic [31:0][4:0] next_indexes;
    logic [9:0] next_length;
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [3:0] compute_next_strategy(
        input logic [511:0] arg_s_deltas,
        input logic [3:0] arg_s_fmt
    );
        logic [3:0] value_next_strategy;
        logic [31:0][4:0] value_next_indexes;
        logic [9:0] value_next_length;
        begin : choose_widths
            int w;
            int n;
            int pb;
            int ib;
            int base_ix;
            int pairs;
            int global_ix;
            int ix0;
            int ix1;
            int pix;
            int global_cost;
            int pair_cost;
            int total;
            int delta_count;
            int pair_ix[0:31];
            value_next_strategy = '0;
            value_next_indexes = '0;
            value_next_length = '0;
            w = 0;
            n = 0;
            pb = 0;
            ib = 0;
            base_ix = 0;
            pairs = 0;
            global_ix = 0;
            ix0 = 0;
            ix1 = 0;
            pix = 0;
            global_cost = 0;
            pair_cost = 0;
            delta_count = 0;
            total = 7;
            for (int p = 0; p < 32; p++) begin
                pair_ix[p] = 0;
            end
            for (int c = 0; c < 4; c++) begin
                if (c < channels(arg_s_fmt)) begin
                    w = width_of(arg_s_fmt, c);
                    n = samples(arg_s_fmt, c);
                    pb = plane_base(arg_s_fmt, c);
                    ib = index_bits(w);
                    base_ix = pair_base(arg_s_fmt, c);
                    pairs = n / 2;
                    global_ix = 0;
                    pair_cost = 1 + pairs * ib;
                    for (int p = 0; p < 32; p++) begin
                        pair_ix[p] = 0;
                        if (p < pairs) begin
                            ix0 = min_index(sample_at(arg_s_deltas, pb + (2 * p + 1) * w, w), w);
                            ix1 = 0;
                            delta_count = 1;
                            if (2 * p + 2 < n) begin
                                ix1 = min_index(sample_at(arg_s_deltas, pb + (2 * p + 2) * w, w), w);
                                delta_count = 2;
                            end
                            pix = ix0 > ix1 ? ix0 : ix1;
                            pair_ix[p] = pix;
                            if (pix > global_ix) begin
                                global_ix = pix;
                            end
                            pair_cost += decode_width(pix, w) * delta_count;
                        end
                    end
                    global_cost = 1 + ib + (n - 1) * decode_width(global_ix, w);
                    if (pair_cost < global_cost) begin
                        value_next_strategy[c] = 1;
                        for (int p = 0; p < 32; p++) begin
                            if (p < pairs) begin
                                value_next_indexes[base_ix + p] = 5'($unsigned(pair_ix[p]));
                            end
                        end
                        total += pair_cost + w;
                    end
                    else begin
                        value_next_indexes[base_ix] = 5'($unsigned(global_ix));
                        total += global_cost + w;
                    end
                end
            end
            value_next_length = 10'($unsigned(total));
        end
        return value_next_strategy;
    endfunction
    assign next_strategy = compute_next_strategy(s_deltas, s_fmt);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [31:0][4:0] compute_next_indexes(
        input logic [511:0] arg_s_deltas,
        input logic [3:0] arg_s_fmt
    );
        logic [3:0] value_next_strategy;
        logic [31:0][4:0] value_next_indexes;
        logic [9:0] value_next_length;
        begin : choose_widths
            int w;
            int n;
            int pb;
            int ib;
            int base_ix;
            int pairs;
            int global_ix;
            int ix0;
            int ix1;
            int pix;
            int global_cost;
            int pair_cost;
            int total;
            int delta_count;
            int pair_ix[0:31];
            value_next_strategy = '0;
            value_next_indexes = '0;
            value_next_length = '0;
            w = 0;
            n = 0;
            pb = 0;
            ib = 0;
            base_ix = 0;
            pairs = 0;
            global_ix = 0;
            ix0 = 0;
            ix1 = 0;
            pix = 0;
            global_cost = 0;
            pair_cost = 0;
            delta_count = 0;
            total = 7;
            for (int p = 0; p < 32; p++) begin
                pair_ix[p] = 0;
            end
            for (int c = 0; c < 4; c++) begin
                if (c < channels(arg_s_fmt)) begin
                    w = width_of(arg_s_fmt, c);
                    n = samples(arg_s_fmt, c);
                    pb = plane_base(arg_s_fmt, c);
                    ib = index_bits(w);
                    base_ix = pair_base(arg_s_fmt, c);
                    pairs = n / 2;
                    global_ix = 0;
                    pair_cost = 1 + pairs * ib;
                    for (int p = 0; p < 32; p++) begin
                        pair_ix[p] = 0;
                        if (p < pairs) begin
                            ix0 = min_index(sample_at(arg_s_deltas, pb + (2 * p + 1) * w, w), w);
                            ix1 = 0;
                            delta_count = 1;
                            if (2 * p + 2 < n) begin
                                ix1 = min_index(sample_at(arg_s_deltas, pb + (2 * p + 2) * w, w), w);
                                delta_count = 2;
                            end
                            pix = ix0 > ix1 ? ix0 : ix1;
                            pair_ix[p] = pix;
                            if (pix > global_ix) begin
                                global_ix = pix;
                            end
                            pair_cost += decode_width(pix, w) * delta_count;
                        end
                    end
                    global_cost = 1 + ib + (n - 1) * decode_width(global_ix, w);
                    if (pair_cost < global_cost) begin
                        value_next_strategy[c] = 1;
                        for (int p = 0; p < 32; p++) begin
                            if (p < pairs) begin
                                value_next_indexes[base_ix + p] = 5'($unsigned(pair_ix[p]));
                            end
                        end
                        total += pair_cost + w;
                    end
                    else begin
                        value_next_indexes[base_ix] = 5'($unsigned(global_ix));
                        total += global_cost + w;
                    end
                end
            end
            value_next_length = 10'($unsigned(total));
        end
        return value_next_indexes;
    endfunction
    assign next_indexes = compute_next_indexes(s_deltas, s_fmt);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [9:0] compute_next_length(
        input logic [511:0] arg_s_deltas,
        input logic [3:0] arg_s_fmt
    );
        logic [3:0] value_next_strategy;
        logic [31:0][4:0] value_next_indexes;
        logic [9:0] value_next_length;
        begin : choose_widths
            int w;
            int n;
            int pb;
            int ib;
            int base_ix;
            int pairs;
            int global_ix;
            int ix0;
            int ix1;
            int pix;
            int global_cost;
            int pair_cost;
            int total;
            int delta_count;
            int pair_ix[0:31];
            value_next_strategy = '0;
            value_next_indexes = '0;
            value_next_length = '0;
            w = 0;
            n = 0;
            pb = 0;
            ib = 0;
            base_ix = 0;
            pairs = 0;
            global_ix = 0;
            ix0 = 0;
            ix1 = 0;
            pix = 0;
            global_cost = 0;
            pair_cost = 0;
            delta_count = 0;
            total = 7;
            for (int p = 0; p < 32; p++) begin
                pair_ix[p] = 0;
            end
            for (int c = 0; c < 4; c++) begin
                if (c < channels(arg_s_fmt)) begin
                    w = width_of(arg_s_fmt, c);
                    n = samples(arg_s_fmt, c);
                    pb = plane_base(arg_s_fmt, c);
                    ib = index_bits(w);
                    base_ix = pair_base(arg_s_fmt, c);
                    pairs = n / 2;
                    global_ix = 0;
                    pair_cost = 1 + pairs * ib;
                    for (int p = 0; p < 32; p++) begin
                        pair_ix[p] = 0;
                        if (p < pairs) begin
                            ix0 = min_index(sample_at(arg_s_deltas, pb + (2 * p + 1) * w, w), w);
                            ix1 = 0;
                            delta_count = 1;
                            if (2 * p + 2 < n) begin
                                ix1 = min_index(sample_at(arg_s_deltas, pb + (2 * p + 2) * w, w), w);
                                delta_count = 2;
                            end
                            pix = ix0 > ix1 ? ix0 : ix1;
                            pair_ix[p] = pix;
                            if (pix > global_ix) begin
                                global_ix = pix;
                            end
                            pair_cost += decode_width(pix, w) * delta_count;
                        end
                    end
                    global_cost = 1 + ib + (n - 1) * decode_width(global_ix, w);
                    if (pair_cost < global_cost) begin
                        value_next_strategy[c] = 1;
                        for (int p = 0; p < 32; p++) begin
                            if (p < pairs) begin
                                value_next_indexes[base_ix + p] = 5'($unsigned(pair_ix[p]));
                            end
                        end
                        total += pair_cost + w;
                    end
                    else begin
                        value_next_indexes[base_ix] = 5'($unsigned(global_ix));
                        total += global_cost + w;
                    end
                end
            end
            value_next_length = 10'($unsigned(total));
        end
        return value_next_length;
    endfunction
    assign next_length = compute_next_length(s_deltas, s_fmt);
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
                    m_decor <= s_decor;
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
                    m_anchors <= s_anchors;
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
                    m_deltas <= s_deltas;
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
                    m_strategy <= next_strategy;
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
                    m_indexes <= next_indexes;
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
                    m_logical_bits <= next_length;
                end
            end
        end
    end
endmodule : udc_enc_index_sel
`default_nettype wire
