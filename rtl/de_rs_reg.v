module de_rs_reg #(
    parameter NORST = 1,
    parameter PLD_W = 256
) (
    input aclk_i,
    input aresetn_i,
    input valid_i,
    input ready_i,
    input [PLD_W-1:0] payload_i,
    output ready_o,
    output valid_o,
    output [PLD_W-1:0] payload_o
);
    wire pipe_wr;
    wire pipe_rd;
    reg [1:0] fifo_valid_cnt;
    reg oetf_pipe_rd;
    reg oetf_pipe_wr;
    reg [1:0] oetf_pipe_avl;
    reg [PLD_W-1:0] oetf_pipe_data [1:0];

    assign ready_o = ~(fifo_valid_cnt >= 2'h2);
    assign pipe_wr = ready_o & valid_i;
    assign pipe_rd = ready_i & valid_o;

    always @(posedge aclk_i or negedge aresetn_i) begin
        if (!aresetn_i) fifo_valid_cnt <= 2'h0;
        else if (pipe_wr & !pipe_rd) fifo_valid_cnt <= fifo_valid_cnt + 1'b1;
        else if (!pipe_wr & pipe_rd) fifo_valid_cnt <= fifo_valid_cnt - 1'b1;
    end
    always @(posedge aclk_i or negedge aresetn_i) begin
        if (!aresetn_i) oetf_pipe_rd <= 1'b0;
        else if (pipe_rd) oetf_pipe_rd <= oetf_pipe_rd + 1'b1;
    end
    always @(posedge aclk_i or negedge aresetn_i) begin
        if (!aresetn_i) oetf_pipe_wr <= 1'b0;
        else if (pipe_wr) oetf_pipe_wr <= oetf_pipe_wr + 1'b1;
    end
    always @(posedge aclk_i or negedge aresetn_i) begin
        if (!aresetn_i) oetf_pipe_avl[0] <= 1'b0;
        else if (pipe_wr & (oetf_pipe_wr == 1'b0)) oetf_pipe_avl[0] <= 1'b1;
        else if (pipe_rd & (oetf_pipe_rd == 1'b0)) oetf_pipe_avl[0] <= 1'b0;
    end
    always @(posedge aclk_i or negedge aresetn_i) begin
        if (!aresetn_i) oetf_pipe_avl[1] <= 1'b0;
        else if (pipe_wr & (oetf_pipe_wr == 1'b1)) oetf_pipe_avl[1] <= 1'b1;
        else if (pipe_rd & (oetf_pipe_rd == 1'b1)) oetf_pipe_avl[1] <= 1'b0;
    end
    if (NORST == 0) begin : GEN_RST
        always @(posedge aclk_i or negedge aresetn_i) begin
            if (!aresetn_i) oetf_pipe_data[0] <= 'h0;
            else if (pipe_wr & (oetf_pipe_wr == 1'b0)) oetf_pipe_data[0] <= payload_i;
        end
        always @(posedge aclk_i or negedge aresetn_i) begin
            if (!aresetn_i) oetf_pipe_data[1] <= 'h0;
            else if (pipe_wr & (oetf_pipe_wr == 1'b1)) oetf_pipe_data[1] <= payload_i;
        end
    end else begin : GEN_NORST
        always @(posedge aclk_i) begin
            if (pipe_wr & (oetf_pipe_wr == 1'b0)) oetf_pipe_data[0] <= payload_i;
        end
        always @(posedge aclk_i) begin
            if (pipe_wr & (oetf_pipe_wr == 1'b1)) oetf_pipe_data[1] <= payload_i;
        end
    end
    assign valid_o = oetf_pipe_avl[oetf_pipe_rd];
    assign payload_o = oetf_pipe_data[oetf_pipe_rd];
endmodule
