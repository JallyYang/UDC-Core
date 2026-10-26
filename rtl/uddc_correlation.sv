// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module uddc_correlation
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
        input logic [6:0] s_size_bytes,
        input logic s_error,
        output logic m_valid,
        input logic m_ready,
        output logic [UNIT_ID_W - 1:0] m_unit_id,
        output logic m_pkg_id,
        output logic [3:0] m_fmt,
        output logic m_decor,
        output logic [511:0] m_planes,
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

    function automatic logic [511:0] color_transform(
            input logic [511:0] v, input logic [3:0] f, input bit inverse);
        logic [511:0] r;
        logic [31:0] x, green, ref_value;
        int w, n, pos;
        r = v;
        x = 0;
        green = 0;
        ref_value = 0;
        w = 0;
        n = 0;
        pos = 0;
        if (can_decor(f)) begin
            for (int c = 0; c < 3; c++) begin
                if (c != 1) begin
                    w = width_of(f, c);
                    n = samples(f, c);
                    for (int k = 0; k < 16; k++) begin
                        if (k < n) begin
                            pos = plane_base(f, c) + k * w;
                            x = sample_at(v, pos, w);
                            green = sample_at(v, plane_base(f, 1) + k * width_of(f, 1), width_of(f, 1));
                            // Green is unsigned; profile 9 requires a logical shift.
                            ref_value = f == 9 && c == 2 ? green >> 1 : green;
                            r = set_sample(r, pos, w, inverse ? x + ref_value : x - ref_value);
                        end
                    end
                end
            end
        end
        return r;
    endfunction
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
                    m_fmt <= s_error ? '0 : s_fmt;
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
                    m_decor <= s_error ? 1'b0 : s_decor;
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
                    m_size_bytes <= s_size_bytes;
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
                    m_error <= s_error;
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
                    m_planes <= s_error ? '0 :
                        (s_decor ? color_transform(s_planes, s_fmt, 1'b1) : s_planes);
                end
            end
        end
    end
endmodule : uddc_correlation
`default_nettype wire
