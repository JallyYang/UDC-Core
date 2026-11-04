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
        // Payload order (MSB to LSB) follows the named port concatenations.
        de_rs_reg #(.NORST(1), .PLD_W(DATA_WIDTH)) u_slice (
            .aclk_i(clk), .aresetn_i(rst_n),
            .valid_i(s_valid), .ready_o(s_ready),
            .ready_i(m_ready), .valid_o(m_valid),
            .payload_i({s_data}),
            .payload_o({m_data})
        );
    end else begin : combinational_stage
        assign s_ready = m_ready;
        assign m_valid = s_valid;
        assign m_data = s_data;
    end
endmodule : uddc_parse_stage
