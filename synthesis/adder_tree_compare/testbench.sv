`timescale 1ns/1ps
module testbench;
    parameter WIDTH = 8;
    localparam SAMPLES = 512 / WIDTH;
    localparam ROW = WIDTH == 32 ? 4 : 8;
    reg clk = 0;
    reg [511:0] delta_in;
    reg [31:0] anchor_in;
    wire [511:0] one_cycle, two_cycles;
    reg [511:0] expected, previous, older;
    integer cycle, word_index, sample_index, parent, seed, unused_random;
    generate
        if (WIDTH == 8) begin
            tree_w8_p1 one(clk, delta_in, anchor_in, one_cycle);
            tree_w8_p2 two(clk, delta_in, anchor_in, two_cycles);
        end else if (WIDTH == 16) begin
            tree_w16_p1 one(clk, delta_in, anchor_in, one_cycle);
            tree_w16_p2 two(clk, delta_in, anchor_in, two_cycles);
        end else begin
            tree_w32_p1 one(clk, delta_in, anchor_in, one_cycle);
            tree_w32_p2 two(clk, delta_in, anchor_in, two_cycles);
        end
    endgenerate
    initial begin
        seed = 84731;
        unused_random = $urandom(seed);
        for (cycle = 0; cycle < 512; cycle = cycle + 1) begin
            for (word_index = 0; word_index < 16; word_index = word_index + 1)
                delta_in[word_index*32 +: 32] = $urandom;
            anchor_in = $urandom;
            if (cycle == 0) begin delta_in = 0; anchor_in = 0; end
            if (cycle == 1) begin delta_in = '1; anchor_in = '1; end
            if (cycle == 2) begin delta_in = {16{32'h80008000}}; anchor_in = 32'h80000000; end
            // Independent serial predictor recurrence, modulo the channel width.
            expected = 0;
            expected[0 +: WIDTH] = anchor_in[0 +: WIDTH];
            for (sample_index = 1; sample_index < SAMPLES; sample_index = sample_index + 1) begin
                parent = sample_index % ROW ? sample_index - 1 : sample_index - ROW;
                expected[sample_index*WIDTH +: WIDTH] =
                    expected[parent*WIDTH +: WIDTH] + delta_in[sample_index*WIDTH +: WIDTH];
            end
            #1; clk = 1; #1;
            // Both designs have the same input-capture register. The tree
            // latency itself is one or two cycles after that launch register.
            if (cycle >= 1 && one_cycle !== previous)
                $fatal(1, "One-cycle mismatch width=%0d cycle=%0d", WIDTH, cycle);
            if (cycle >= 2 && two_cycles !== older)
                $fatal(1, "Two-cycle mismatch width=%0d cycle=%0d", WIDTH, cycle);
            older = previous;
            previous = expected;
            clk = 0;
        end
        $display("PASS width=%0d: both pipelines match predictor recurrence; 512 input vectors", WIDTH);
        $finish;
    end
endmodule
