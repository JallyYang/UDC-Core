// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

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
    typedef struct packed {
        logic [511:0] sums;
        logic [3:0][31:0] anchors;
        logic [3:0] format_id;
        logic [UNIT_ID_W-1:0] unit_id;
        logic package_id;
        logic decor;
        logic error;
        logic [6:0] size_bytes;
    } stage_data_t;
    stage_data_t stage_data[0:LAST_STAGE];
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

    function automatic logic [511:0] restore_anchors(input stage_data_t data);
        logic [511:0] result;
        int w;
        int n;
        int pb;
        result = '0;
        for (int c = 0; c < 4; c++) begin
            w = width_of(data.format_id, c);
            n = samples(data.format_id, c);
            pb = plane_base(data.format_id, c);
            for (int k = 0; k < 64; k++) begin
                if (k < n && !data.error)
                    result = set_sample(result, pb + k*w, w,
                        sample_at(data.sums, pb + k*w, w) + data.anchors[c]);
            end
        end
        return result;
    endfunction

    assign s_ready = stage_ready[0];
    assign m_valid = stage_valid[LAST_STAGE];
    assign m_unit_id = stage_data[LAST_STAGE].unit_id;
    assign m_pkg_id = stage_data[LAST_STAGE].package_id;
    assign m_fmt = stage_data[LAST_STAGE].format_id;
    assign m_decor = stage_data[LAST_STAGE].decor;
    assign m_size_bytes = stage_data[LAST_STAGE].size_bytes;
    assign m_error = stage_data[LAST_STAGE].error;
    assign m_planes = restore_anchors(stage_data[LAST_STAGE]);

    // The first register performs distance-1 accumulation directly. There is
    // no separate register that only copies input deltas before computation.
    for (genvar stage_index = 0; stage_index < PIPELINE_STAGES; stage_index++) begin : prefix_stage
        stage_data_t next_data;
        logic input_valid;
        if (stage_index == 0) begin : first_stage
            assign input_valid = s_valid;
            assign next_data.sums = accumulate_deltas(s_deltas, s_fmt, s_error, 1);
            assign next_data.anchors = s_error ? '0 : s_anchors;
            assign next_data.format_id = s_error ? '0 : s_fmt;
            assign next_data.unit_id = s_unit_id;
            assign next_data.package_id = s_pkg_id;
            assign next_data.decor = s_decor;
            assign next_data.error = s_error;
            assign next_data.size_bytes = s_size_bytes;
        end else begin : following_stage
            assign input_valid = stage_valid[stage_index-1];
            assign next_data.sums = accumulate_deltas(stage_data[stage_index-1].sums,
                    stage_data[stage_index-1].format_id,
                    stage_data[stage_index-1].error, 1 << stage_index);
            assign next_data.anchors = stage_data[stage_index-1].anchors;
            assign next_data.format_id = stage_data[stage_index-1].format_id;
            assign next_data.unit_id = stage_data[stage_index-1].unit_id;
            assign next_data.package_id = stage_data[stage_index-1].package_id;
            assign next_data.decor = stage_data[stage_index-1].decor;
            assign next_data.error = stage_data[stage_index-1].error;
            assign next_data.size_bytes = stage_data[stage_index-1].size_bytes;
        end
        if (stage_index == LAST_STAGE) begin : last_ready
            assign stage_ready[stage_index] = !stage_valid[stage_index] || m_ready;
        end else begin : following_ready
            assign stage_ready[stage_index] = !stage_valid[stage_index] || stage_ready[stage_index+1];
        end
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                stage_valid[stage_index] <= 0;
            end else if (stage_ready[stage_index]) begin
                stage_valid[stage_index] <= input_valid;
            end
        end
        always_ff @(posedge clk) begin
            if (rst_n && stage_ready[stage_index] && input_valid)
                stage_data[stage_index].sums <= next_data.sums;
        end

        always_ff @(posedge clk) begin
            if (rst_n && stage_ready[stage_index] && input_valid)
                stage_data[stage_index].anchors <= next_data.anchors;
        end

        always_ff @(posedge clk) begin
            if (rst_n && stage_ready[stage_index] && input_valid)
                stage_data[stage_index].format_id <= next_data.format_id;
        end

        always_ff @(posedge clk) begin
            if (rst_n && stage_ready[stage_index] && input_valid)
                stage_data[stage_index].unit_id <= next_data.unit_id;
        end

        always_ff @(posedge clk) begin
            if (rst_n && stage_ready[stage_index] && input_valid)
                stage_data[stage_index].package_id <= next_data.package_id;
        end

        always_ff @(posedge clk) begin
            if (rst_n && stage_ready[stage_index] && input_valid)
                stage_data[stage_index].decor <= next_data.decor;
        end

        always_ff @(posedge clk) begin
            if (rst_n && stage_ready[stage_index] && input_valid)
                stage_data[stage_index].error <= next_data.error;
        end

        always_ff @(posedge clk) begin
            if (rst_n && stage_ready[stage_index] && input_valid)
                stage_data[stage_index].size_bytes <= next_data.size_bytes;
        end

    end
endmodule : uddc_delta_cal
`default_nettype wire
