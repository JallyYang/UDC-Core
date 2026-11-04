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
    logic select_saved;
    assign select_saved = can_decor(s_fmt) && s_decor && s_logical_bits >= saved_length;
    // Payload order (MSB to LSB) follows the named port concatenations.
    de_rs_reg #(.NORST(1), .PLD_W(UNIT_ID_W+1+4+1+128+512+4+160+10)) u_output_slice (
        .aclk_i(clk), .aresetn_i(rst_n),
        .valid_i(s_valid && (!can_decor(s_fmt) || s_decor)), .ready_o(s_ready),
        .ready_i(m_ready), .valid_o(m_valid),
        .payload_i({s_unit_id, s_pkg_id, s_fmt, select_saved ? 1'b0 : s_decor, select_saved ? saved_anchors : s_anchors, select_saved ? saved_deltas : s_deltas, select_saved ? saved_strategy : s_strategy, select_saved ? saved_indexes : s_indexes, select_saved ? saved_length : s_logical_bits}),
        .payload_o({m_unit_id, m_pkg_id, m_fmt, m_decor, m_anchors, m_deltas, m_strategy, m_indexes, m_logical_bits})
    );


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

endmodule : udc_enc_candidate_sel
