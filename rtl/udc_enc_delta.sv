// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module udc_enc_delta
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
        input logic [511:0] s_planes,
        output logic m_valid,
        input logic m_ready,
        output logic [UNIT_ID_W - 1:0] m_unit_id,
        output logic m_pkg_id,
        output logic [3:0] m_fmt,
        output logic m_decor,
        output logic [3:0][31:0] m_anchors,
        output logic [511:0] m_deltas
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

    function automatic int row_width(input logic [3:0] f);
        case (f)
            1, 2, 6: begin
                return 8;
            end
            3, 4, 7, 8, 9, 10, 11, 12, 13: begin
                return 4;
            end
            5: begin
                return 2;
            end
            default: begin
                return 1;
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

    function automatic logic [31:0] mask_w(input int w);
        return w == 32 ? 32'hffffffff : ((32'h1 << w) - 1);
    endfunction

    function automatic logic [31:0] sample_at(
            input logic [511:0] v, input int pos, input int w);
        return 32'(v >> pos) & mask_w(w);
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
    logic [511:0] next_delta;
    logic [3:0][31:0] next_anchor;
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [511:0] compute_next_delta(
            input logic [3:0] arg_s_fmt,
            input logic [511:0] arg_s_planes);
        logic [511:0] value_next_delta;
        logic [3:0][31:0] value_next_anchor;
        begin : difference
            int w, n, pb, pred, rw;
            logic [31:0] x, p;
            value_next_delta = '0;
            value_next_anchor = '0;
            w = 0;
            n = 0;
            pb = 0;
            pred = 0;
            rw = row_width(arg_s_fmt);
            x = 0;
            p = 0;
            for (int c = 0; c < 4; c++) begin
                w = width_of(arg_s_fmt, c);
                n = samples(arg_s_fmt, c);
                pb = plane_base(arg_s_fmt, c);
                if (n > 0) begin
                    value_next_anchor[c] = sample_at(arg_s_planes, pb, w);
                end
                for (int k = 1; k < 64; k++) begin
                    if (k < n) begin
                        pred = arg_s_fmt == 14 || (k % rw) != 0 ? k - 1 : k - rw;
                        x = sample_at(arg_s_planes, pb + k * w, w);
                        p = sample_at(arg_s_planes, pb + pred * w, w);
                        value_next_delta = set_sample(value_next_delta, pb + k * w, w, x - p);
                    end
                end
            end
        end
        return value_next_delta;
    endfunction
    assign next_delta = compute_next_delta(s_fmt, s_planes);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [3:0][31:0] compute_next_anchor(
            input logic [3:0] arg_s_fmt,
            input logic [511:0] arg_s_planes);
        logic [511:0] value_next_delta;
        logic [3:0][31:0] value_next_anchor;
        begin : difference
            int w, n, pb, pred, rw;
            logic [31:0] x, p;
            value_next_delta = '0;
            value_next_anchor = '0;
            w = 0;
            n = 0;
            pb = 0;
            pred = 0;
            rw = row_width(arg_s_fmt);
            x = 0;
            p = 0;
            for (int c = 0; c < 4; c++) begin
                w = width_of(arg_s_fmt, c);
                n = samples(arg_s_fmt, c);
                pb = plane_base(arg_s_fmt, c);
                if (n > 0) begin
                    value_next_anchor[c] = sample_at(arg_s_planes, pb, w);
                end
                for (int k = 1; k < 64; k++) begin
                    if (k < n) begin
                        pred = arg_s_fmt == 14 || (k % rw) != 0 ? k - 1 : k - rw;
                        x = sample_at(arg_s_planes, pb + k * w, w);
                        p = sample_at(arg_s_planes, pb + pred * w, w);
                        value_next_delta = set_sample(value_next_delta, pb + k * w, w, x - p);
                    end
                end
            end
        end
        return value_next_anchor;
    endfunction
    assign next_anchor = compute_next_anchor(s_fmt, s_planes);
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
                    m_anchors <= next_anchor;
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
                    m_deltas <= next_delta;
                end
            end
        end
    end
endmodule : udc_enc_delta
`default_nettype wire
