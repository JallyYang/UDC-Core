module de_rs_reg_test (
    input logic clk,
    input logic rst_n,
    input logic [7:0] input_valid,
    input logic [7:0] output_ready,
    input logic [7:0][1023:0] input_payload,
    output wire [7:0] input_ready,
    output wire [7:0] output_valid,
    output wire [7:0][1023:0] output_payload
);
    for (genvar lane = 0; lane < 8; lane++) begin : test_lane
        localparam int WIDTH = lane % 4 == 0 ? 1 :
                               lane % 4 == 1 ? 32 :
                               lane % 4 == 2 ? 256 : 1024;
        wire [WIDTH-1:0] payload;
        de_rs_reg #(.NORST(lane / 4), .PLD_W(WIDTH)) u_slice (
            .aclk_i(clk), .aresetn_i(rst_n),
            .valid_i(input_valid[lane]), .ready_o(input_ready[lane]),
            .ready_i(output_ready[lane]), .valid_o(output_valid[lane]),
            .payload_i(input_payload[lane][WIDTH-1:0]), .payload_o(payload)
        );
        assign output_payload[lane] = 1024'(payload);
    end
endmodule
