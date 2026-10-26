// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module udc_clear_check
    #(
        parameter int unsigned UNIT_ID_W = 4
    )
    (
        input logic clk,
        input logic rst_n,
        input logic [9:0][127:0] cfg_clear_pattern,
        input logic s_valid,
        output logic s_ready,
        input logic [UNIT_ID_W - 1:0] s_unit_id,
        input logic s_sop,
        input logic s_last,
        input logic [255:0] s_data,
        output logic m_valid,
        input logic m_ready,
        output logic [UNIT_ID_W - 1:0] m_unit_id,
        output logic m_hit,
        output logic [3:0] m_index
    );
    logic [9:0] match_q, match_now, combined;
    logic [3:0] index_now;
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [9:0] compute_match_now(
            input logic [9:0][127:0] arg_cfg_clear_pattern,
            input logic [9:0] arg_match_q,
            input logic [255:0] arg_s_data,
            input logic arg_s_sop);
        logic [9:0] value_match_now;
        logic [9:0] value_combined;
        logic [3:0] value_index_now;
        begin
            for (int i = 0; i < 10; i++) begin
                // A 32-byte beat contains two copies of the same 16-byte pattern.
                value_match_now[i] = arg_s_data == {2{arg_cfg_clear_pattern[i]}};
            end
            value_combined = value_match_now & (arg_s_sop ? 10'h3ff : arg_match_q);
            value_index_now = 0;
            for (int i = 9; i >= 0; i--) begin
                if (value_combined[i]) begin
                    value_index_now = 4'($unsigned(i));
                end
            end
        end
        return value_match_now;
    endfunction
    assign match_now = compute_match_now(cfg_clear_pattern, match_q, s_data, s_sop);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [9:0] compute_combined(
            input logic [9:0][127:0] arg_cfg_clear_pattern,
            input logic [9:0] arg_match_q,
            input logic [255:0] arg_s_data,
            input logic arg_s_sop);
        logic [9:0] value_match_now;
        logic [9:0] value_combined;
        logic [3:0] value_index_now;
        begin
            for (int i = 0; i < 10; i++) begin
                // A 32-byte beat contains two copies of the same 16-byte pattern.
                value_match_now[i] = arg_s_data == {2{arg_cfg_clear_pattern[i]}};
            end
            value_combined = value_match_now & (arg_s_sop ? 10'h3ff : arg_match_q);
            value_index_now = 0;
            for (int i = 9; i >= 0; i--) begin
                if (value_combined[i]) begin
                    value_index_now = 4'($unsigned(i));
                end
            end
        end
        return value_combined;
    endfunction
    assign combined = compute_combined(cfg_clear_pattern, match_q, s_data, s_sop);
    // Pure combinational calculation; one result, no module-state side effects.

    function automatic logic [3:0] compute_index_now(
            input logic [9:0][127:0] arg_cfg_clear_pattern,
            input logic [9:0] arg_match_q,
            input logic [255:0] arg_s_data,
            input logic arg_s_sop);
        logic [9:0] value_match_now;
        logic [9:0] value_combined;
        logic [3:0] value_index_now;
        begin
            for (int i = 0; i < 10; i++) begin
                // A 32-byte beat contains two copies of the same 16-byte pattern.
                value_match_now[i] = arg_s_data == {2{arg_cfg_clear_pattern[i]}};
            end
            value_combined = value_match_now & (arg_s_sop ? 10'h3ff : arg_match_q);
            value_index_now = 0;
            for (int i = 9; i >= 0; i--) begin
                if (value_combined[i]) begin
                    value_index_now = 4'($unsigned(i));
                end
            end
        end
        return value_index_now;
    endfunction
    assign index_now = compute_index_now(cfg_clear_pattern, match_q, s_data, s_sop);
    assign s_ready = !m_valid || m_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid <= 0;
        end
        else begin
            if (m_valid && m_ready) begin
                m_valid <= 0;
            end
            if (s_valid && s_ready) begin
                if (s_last) begin
                    m_valid <= 1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            match_q <= 0;
        end
        else begin
            if (s_valid && s_ready) begin
                match_q <= combined;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                if (s_last) begin
                    m_unit_id <= s_unit_id;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                if (s_last) begin
                    m_hit <= | combined;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else begin
            if (s_valid && s_ready) begin
                if (s_last) begin
                    m_index <= index_now;
                end
            end
        end
    end
    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n && s_valid && s_ready && s_last)
        begin
            assert($onehot0(combined)) else begin
                $error("Multiple clear patterns matched");
            end
        end
    end
    // synthesis translate_on
endmodule : udc_clear_check
`default_nettype wire
