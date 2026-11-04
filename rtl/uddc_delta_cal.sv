module uddc_delta_cal
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
    localparam int PIPELINE_STAGES = 4;
    localparam int LAST_STAGE = PIPELINE_STAGES - 1;
    logic [511:0] stage_sums [0:LAST_STAGE];
    logic [3:0][31:0] stage_anchors [0:LAST_STAGE];
    logic [3:0] stage_format_id [0:LAST_STAGE];
    logic [UNIT_ID_W-1:0] stage_unit_id [0:LAST_STAGE];
    logic stage_package_id [0:LAST_STAGE];
    logic stage_decor [0:LAST_STAGE];
    logic stage_error [0:LAST_STAGE];
    logic [6:0] stage_size_bytes [0:LAST_STAGE];
    logic [LAST_STAGE:0] stage_valid;
    logic [LAST_STAGE:0] stage_ready;
    function automatic int ancestor(
        input int k,
        input int distance,
        input int rw,
        input bit linear
    );
        int v;
        v = k;
        for (int step = 0; step < 8; step++) begin
            if (step < distance && v > 0)
            begin
                v = linear || v % rw != 0 ? v - 1 : v - rw;
            end
        end
        return v;
    endfunction

    function automatic logic [511:0] accumulate_deltas(
        input logic [511:0] values,
        input logic [3:0] format_id,
        input logic error,
        input int distance
    );
        logic [511:0] result;
        int w;
        int n;
        int pb;
        int parent;
        result = '0;
        for (int c = 0; c < 4; c++) begin
            w = width_of(format_id, c);
            n = samples(format_id, c);
            pb = plane_base(format_id, c);
            for (int k = 0; k < 64; k++) begin
                if (k < n && !error) begin
                    parent = ancestor(k, distance, row_width(format_id), format_id == 14);
                    result = set_sample(result, pb + k*w, w,
                        sample_at(values, pb + k*w, w) +
                        sample_at(values, pb + parent*w, w));
                end
            end
        end
        return result;
    endfunction

    function automatic logic [511:0] restore_anchors(
        input logic [511:0] sums,
        input logic [3:0][31:0] anchors,
        input logic [3:0] format_id,
        input logic error
    );
        logic [511:0] result;
        int w;
        int n;
        int pb;
        result = '0;
        for (int c = 0; c < 4; c++) begin
            w = width_of(format_id, c);
            n = samples(format_id, c);
            pb = plane_base(format_id, c);
            for (int k = 0; k < 64; k++) begin
                if (k < n && !error)
                    result = set_sample(result, pb + k*w, w,
                        sample_at(sums, pb + k*w, w) + anchors[c]);
            end
        end
        return result;
    endfunction

    assign s_ready = stage_ready[0];
    assign m_valid = stage_valid[LAST_STAGE];
    assign m_unit_id = stage_unit_id[LAST_STAGE];
    assign m_pkg_id = stage_package_id[LAST_STAGE];
    assign m_fmt = stage_format_id[LAST_STAGE];
    assign m_decor = stage_decor[LAST_STAGE];
    assign m_size_bytes = stage_size_bytes[LAST_STAGE];
    assign m_error = stage_error[LAST_STAGE];
    assign m_planes = restore_anchors(stage_sums[LAST_STAGE],stage_anchors[LAST_STAGE],stage_format_id[LAST_STAGE],stage_error[LAST_STAGE]);

    // The first register performs distance-1 accumulation directly. There is
    // no separate register that only copies input deltas before computation.
    for (genvar stage_index = 0; stage_index < PIPELINE_STAGES; stage_index++) begin : prefix_stage
        logic [511:0] next_sums;
        logic [3:0][31:0] next_anchors;
        logic [3:0] next_format_id;
        logic [UNIT_ID_W-1:0] next_unit_id;
        logic next_package_id;
        logic next_decor;
        logic next_error;
        logic [6:0] next_size_bytes;
        logic input_valid;
        if (stage_index == 0) begin : first_stage
            assign input_valid = s_valid;
            assign next_sums = accumulate_deltas(s_deltas, s_fmt, s_error, 1);
            assign next_anchors = s_error ? '0 : s_anchors;
            assign next_format_id = s_error ? '0 : s_fmt;
            assign next_unit_id = s_unit_id;
            assign next_package_id = s_pkg_id;
            assign next_decor = s_decor;
            assign next_error = s_error;
            assign next_size_bytes = s_size_bytes;
        end else begin : following_stage
            assign input_valid = stage_valid[stage_index-1];
            assign next_sums = accumulate_deltas(stage_sums[stage_index-1],
                    stage_format_id[stage_index-1],
                    stage_error[stage_index-1], 1 << stage_index);
            assign next_anchors = stage_anchors[stage_index-1];
            assign next_format_id = stage_format_id[stage_index-1];
            assign next_unit_id = stage_unit_id[stage_index-1];
            assign next_package_id = stage_package_id[stage_index-1];
            assign next_decor = stage_decor[stage_index-1];
            assign next_error = stage_error[stage_index-1];
            assign next_size_bytes = stage_size_bytes[stage_index-1];
        end
        logic output_ready;
        if (stage_index == LAST_STAGE) begin : last_ready
            assign output_ready = m_ready;
        end else begin : following_ready
            assign output_ready = stage_ready[stage_index+1];
        end
        // Payload order (MSB to LSB) follows the named port concatenations.
        de_rs_reg #(.NORST(1), .PLD_W(512+128+4+UNIT_ID_W+1+1+1+7)) u_slice (
            .aclk_i(clk), .aresetn_i(rst_n),
            .valid_i(input_valid), .ready_o(stage_ready[stage_index]),
            .ready_i(output_ready), .valid_o(stage_valid[stage_index]),
            .payload_i({next_sums, next_anchors, next_format_id, next_unit_id, next_package_id, next_decor, next_error, next_size_bytes}),
            .payload_o({stage_sums[stage_index], stage_anchors[stage_index], stage_format_id[stage_index], stage_unit_id[stage_index], stage_package_id[stage_index], stage_decor[stage_index], stage_error[stage_index], stage_size_bytes[stage_index]})
        );

    end
endmodule : uddc_delta_cal
