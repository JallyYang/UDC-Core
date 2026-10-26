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
    localparam int STAGES = 4;
    logic [STAGES:0] valid_q;
    logic [STAGES:0] ready_q;
    logic [511:0] sum_q[0:STAGES];
    logic [3:0][31:0] anchor_q[0:STAGES];
    logic [3:0] fmt_q[0:STAGES];
    logic [UNIT_ID_W - 1:0] id_q[0:STAGES];
    logic pkg_q[0:STAGES], decor_q[0:STAGES], error_q[0:STAGES];
    logic [6:0] size_q[0:STAGES];

    function automatic int ancestor(input int k, input int distance,
            input int rw, input bit linear);
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
    assign ready_q[STAGES] = !valid_q[STAGES] || m_ready;
    for (genvar g = 0; g < STAGES; g++) begin : ready_link
        assign ready_q[g] = !valid_q[g] || ready_q[g + 1];
    end
    assign s_ready = ready_q[0];
    assign m_valid = valid_q[STAGES];
    assign m_unit_id = id_q[STAGES];
    assign m_pkg_id = pkg_q[STAGES];
    assign m_fmt = fmt_q[STAGES];
    assign m_decor = decor_q[STAGES];
    assign m_size_bytes = size_q[STAGES];
    assign m_error = error_q[STAGES];
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [511:0] compute_m_planes(
            input logic [3:0][31:0] arg_anchor_q[0:STAGES],
            input logic arg_error_q[0:STAGES],
            input logic [3:0] arg_fmt_q[0:STAGES],
            input logic [511:0] arg_sum_q[0:STAGES]);
        logic [511:0] value_m_planes;
        begin : add_anchors
            int w, n, pb;
            value_m_planes = '0;
            w = 0;
            n = 0;
            pb = 0;
            for (int c = 0; c < 4; c++) begin
                w = width_of(arg_fmt_q[STAGES], c);
                n = samples(arg_fmt_q[STAGES], c);
                pb = plane_base(arg_fmt_q[STAGES], c);
                for (int k = 0; k < 64; k++) begin
                    if (k < n && !arg_error_q[STAGES])
                    begin
                        value_m_planes = set_sample(value_m_planes, pb + k * w, w,
                            sample_at(arg_sum_q[STAGES], pb + k * w, w) + arg_anchor_q[STAGES][c]);
                    end
                end
            end
        end
        return value_m_planes;
    endfunction
    assign m_planes = compute_m_planes(anchor_q, error_q, fmt_q, sum_q);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_q[0] <= 0;
        end
        else begin
            if (ready_q[0]) begin
                valid_q[0] <= s_valid;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (ready_q[0]) begin
                if (s_valid) begin
                    sum_q[0] <= s_error ? '0 : s_deltas;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (ready_q[0]) begin
                if (s_valid) begin
                    if (s_error) begin
                        anchor_q[0] <= '0;
                    end
                    else begin
                        anchor_q[0] <= s_anchors;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (ready_q[0]) begin
                if (s_valid) begin
                    fmt_q[0] <= s_error ? '0 : s_fmt;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (ready_q[0]) begin
                if (s_valid) begin
                    id_q[0] <= s_unit_id;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (ready_q[0]) begin
                if (s_valid) begin
                    pkg_q[0] <= s_pkg_id;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (ready_q[0]) begin
                if (s_valid) begin
                    decor_q[0] <= s_decor;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (ready_q[0]) begin
                if (s_valid) begin
                    error_q[0] <= s_error;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (ready_q[0]) begin
                if (s_valid) begin
                    size_q[0] <= s_size_bytes;
                end
            end
        end
    end
    for (genvar g = 0; g < STAGES; g++) begin : prefix_stage
        logic [511:0] sum_next;
        // Pure combinational calculation; one result, no module-state side effects.

        function automatic logic [511:0] compute_sum_next(
                input logic arg_error_q[0:STAGES],
                input logic [3:0] arg_fmt_q[0:STAGES],
                input logic [511:0] arg_sum_q[0:STAGES]);
            logic [511:0] value_sum_next;
            begin
                int w, n, pb, parent;
                value_sum_next = '0;
                w = 0;
                n = 0;
                pb = 0;
                parent = 0;
                for (int c = 0; c < 4; c++) begin
                    w = width_of(arg_fmt_q[g], c);
                    n = samples(arg_fmt_q[g], c);
                    pb = plane_base(arg_fmt_q[g], c);
                    for (int k = 0; k < 64; k++) begin
                        if (k < n && !arg_error_q[g]) begin
                            parent = ancestor(k, 1 << g, row_width(arg_fmt_q[g]), arg_fmt_q[g] == 14);
                            value_sum_next = set_sample(value_sum_next, pb + k * w, w,
                                sample_at(arg_sum_q[g], pb + k * w, w) + sample_at(arg_sum_q[g], pb + parent * w, w));
                        end
                    end
                end
            end
            return value_sum_next;
        endfunction
        assign sum_next = compute_sum_next(error_q, fmt_q, sum_q);

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                valid_q[g + 1] <= 0;
            end
            else begin
                if (ready_q[g + 1]) begin
                    valid_q[g + 1] <= valid_q[g];
                end
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
            end
            else begin
                if (ready_q[g + 1]) begin
                    if (valid_q[g]) begin
                        sum_q[g + 1] <= sum_next;
                    end
                end
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
            end
            else begin
                if (ready_q[g + 1]) begin
                    if (valid_q[g]) begin
                        anchor_q[g + 1] <= anchor_q[g];
                    end
                end
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
            end
            else begin
                if (ready_q[g + 1]) begin
                    if (valid_q[g]) begin
                        fmt_q[g + 1] <= fmt_q[g];
                    end
                end
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
            end
            else begin
                if (ready_q[g + 1]) begin
                    if (valid_q[g]) begin
                        id_q[g + 1] <= id_q[g];
                    end
                end
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
            end
            else begin
                if (ready_q[g + 1]) begin
                    if (valid_q[g]) begin
                        pkg_q[g + 1] <= pkg_q[g];
                    end
                end
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
            end
            else begin
                if (ready_q[g + 1]) begin
                    if (valid_q[g]) begin
                        decor_q[g + 1] <= decor_q[g];
                    end
                end
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
            end
            else begin
                if (ready_q[g + 1]) begin
                    if (valid_q[g]) begin
                        error_q[g + 1] <= error_q[g];
                    end
                end
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
            end
            else begin
                if (ready_q[g + 1]) begin
                    if (valid_q[g]) begin
                        size_q[g + 1] <= size_q[g];
                    end
                end
            end
        end
    end
endmodule : uddc_delta_cal
`default_nettype wire
