// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module uddc_clear_recon
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
        input logic [3:0] s_index,
        output logic m_valid,
        input logic m_ready,
        output logic [UNIT_ID_W - 1:0] m_unit_id,
        output logic [1023:0] m_raw
    );
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
                    m_raw <= s_index < 10 ? {8{cfg_clear_pattern[s_index]}} : '0;
                end
            end
        end
    end
endmodule : uddc_clear_recon
`default_nettype wire
