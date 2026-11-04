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
    localparam int OUTPUT_WIDTH = UNIT_ID_W+1024;

    // Payload order (MSB to LSB) follows the named port concatenations.
    de_rs_reg #(.NORST(1), .PLD_W(OUTPUT_WIDTH)) u_output_slice (
        .aclk_i(clk), .aresetn_i(rst_n),
        .valid_i(s_valid), .ready_o(s_ready),
        .ready_i(m_ready), .valid_o(m_valid),
        .payload_i({s_unit_id, s_index < 10 ? {8{cfg_clear_pattern[s_index]}} : '0}),
        .payload_o({m_unit_id, m_raw})
    );

endmodule : uddc_clear_recon
