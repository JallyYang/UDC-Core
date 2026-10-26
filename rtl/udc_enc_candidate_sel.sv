// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module udc_enc_candidate_sel
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
        output logic m_decor,
        output logic [3:0][31:0] m_anchors,
        output logic [511:0] m_deltas,
        output logic [3:0] m_strategy,
        output logic [31:0][4:0] m_indexes,
        output logic [9:0] m_logical_bits
    );

    function automatic bit can_decor(input logic [3:0] f);
        return f == 4 || f == 5 || f == 9 || f == 10 || f == 11;
    endfunction
    logic [3:0][31:0] saved_anchors;
    logic [511:0] saved_deltas;
    logic [3:0] saved_strategy;
    logic [31:0][4:0] saved_indexes;
    logic [9:0] saved_length;
    logic waiting;
    logic [UNIT_ID_W - 1:0] saved_id;
    logic saved_pkg;
    assign s_ready = !m_valid || m_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid <= 0;
        end
        else begin
            if (s_ready) begin
                m_valid <= 0;
                if (s_valid) begin
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        m_valid <= 1;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            waiting <= 0;
        end
        else begin
            if (s_ready) begin
                if (s_valid) begin
                    if (can_decor(s_fmt) && !s_decor) begin
                        waiting <= 1;
                    end
                    else begin
                        waiting <= 0;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                        saved_anchors <= s_anchors;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                        saved_deltas <= s_deltas;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                        saved_strategy <= s_strategy;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                        saved_indexes <= s_indexes;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                        saved_length <= s_logical_bits;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                        saved_id <= s_unit_id;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                        saved_pkg <= s_pkg_id;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        m_unit_id <= s_unit_id;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        m_pkg_id <= s_pkg_id;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        m_fmt <= s_fmt;
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        if (can_decor(s_fmt) && s_decor && s_logical_bits >= saved_length) begin
                            m_decor <= 0;
                        end
                        else begin
                            m_decor <= s_decor;
                        end
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        if (can_decor(s_fmt) && s_decor && s_logical_bits >= saved_length) begin
                            m_anchors <= saved_anchors;
                        end
                        else begin
                            m_anchors <= s_anchors;
                        end
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        if (can_decor(s_fmt) && s_decor && s_logical_bits >= saved_length) begin
                            m_deltas <= saved_deltas;
                        end
                        else begin
                            m_deltas <= s_deltas;
                        end
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        if (can_decor(s_fmt) && s_decor && s_logical_bits >= saved_length) begin
                            m_strategy <= saved_strategy;
                        end
                        else begin
                            m_strategy <= s_strategy;
                        end
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        if (can_decor(s_fmt) && s_decor && s_logical_bits >= saved_length) begin
                            m_indexes <= saved_indexes;
                        end
                        else begin
                            m_indexes <= s_indexes;
                        end
                    end
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
                    if (can_decor(s_fmt) && !s_decor) begin
                    end
                    else begin
                        if (can_decor(s_fmt) && s_decor && s_logical_bits >= saved_length) begin
                            m_logical_bits <= saved_length;
                        end
                        else begin
                            m_logical_bits <= s_logical_bits;
                        end
                    end
                end
            end
        end
    end
    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n && s_valid && s_ready && s_decor)
        begin
            assert(waiting && saved_id == s_unit_id && saved_pkg == s_pkg_id)
            else begin
                $error("Candidate order/tag mismatch");
            end
        end
    end
    // synthesis translate_on
endmodule : udc_enc_candidate_sel
`default_nettype wire
