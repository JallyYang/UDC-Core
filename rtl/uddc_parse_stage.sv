module uddc_parse_stage #(
    parameter bit REGISTERED = 1'b1,
    parameter int unsigned DATA_WIDTH = 1
) (
    input logic clk,
    input logic rst_n,
    input logic s_valid,
    output logic s_ready,
    input logic [DATA_WIDTH-1:0] s_data,
    output logic m_valid,
    input logic m_ready,
    output logic [DATA_WIDTH-1:0] m_data
);
    // The bypass branch forwards data, valid and ready without a clock.
    if (REGISTERED) begin : registered_stage
        assign s_ready = !m_valid || m_ready;
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) m_valid <= 1'b0;
            else if (s_ready) m_valid <= s_valid;
        end
        always_ff @(posedge clk) begin
            if (rst_n && s_ready && s_valid) m_data <= s_data;
        end
    end else begin : combinational_stage
        assign s_ready = m_ready;
        assign m_valid = s_valid;
        assign m_data = s_data;
    end
endmodule : uddc_parse_stage
