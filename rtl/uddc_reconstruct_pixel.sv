module uddc_reconstruct_pixel
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
        output logic [511:0] m_raw,
        output logic [6:0] m_size_bytes,
        output logic m_error
    );

    localparam int OUTPUT_WIDTH = UNIT_ID_W+1+4+7+1+512;
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

    function automatic logic [511:0] set_sample(
        input logic [511:0] v,
        input int pos,
        input int w,
        input logic [31:0] x
    );
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

    function automatic logic [511:0] transpose_planes(
        input logic [511:0] v,
        input logic [3:0] f,
        input bit inverse
    );
        logic [511:0] r;
        int pixel_w;
        int offset;
        int w;
        int n;
        int pb;
        int raw_pos;
        r = '0;
        pixel_w = 0;
        for (int c = 0; c < 4; c++) begin
            pixel_w += width_of(f, c);
        end
        offset = 0;
        for (int c = 0; c < 4; c++) begin
            w = width_of(f, c);
            n = samples(f, c);
            pb = plane_base(f, c);
            for (int k = 0; k < 64; k++) begin
                if (k < n) begin
                    raw_pos = f == 14 ? (3 * k + c) * 32 : k * pixel_w + offset;
                    if (inverse) begin
                        r = set_sample(r, raw_pos, w, sample_at(v, pb + k * w, w));
                    end
                    else begin
                        r = set_sample(r, pb + k * w, w, sample_at(v, raw_pos, w));
                    end
                end
            end
            offset += w;
        end
        return r;
    endfunction
    // Payload order (MSB to LSB) follows the named port concatenations.
    de_rs_reg #(.NORST(1), .PLD_W(OUTPUT_WIDTH)) u_output_slice (
        .aclk_i(clk), .aresetn_i(rst_n),
        .valid_i(s_valid), .ready_o(s_ready),
        .ready_i(m_ready), .valid_o(m_valid),
        .payload_i({s_unit_id, s_pkg_id, s_error ? '0 : s_fmt, s_size_bytes, s_error, s_error ? '0 : transpose_planes(s_planes, s_fmt, 1'b1)}),
        .payload_o({m_unit_id, m_pkg_id, m_fmt, m_size_bytes, m_error, m_raw})
    );

endmodule : uddc_reconstruct_pixel
