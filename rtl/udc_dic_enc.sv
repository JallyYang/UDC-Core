// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module udc_dic_enc
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
        input logic [511:0] s_raw,
        output logic m_valid,
        input logic m_ready,
        output logic [UNIT_ID_W - 1:0] m_unit_id,
        output logic m_pkg_id,
        output logic [3:0] m_fmt,
        output logic [6:0] m_size_bytes,
        output logic [543:0] m_bits,
        output logic m_error
    );
    logic a_valid;
    logic a_ready;
    logic [UNIT_ID_W - 1:0] a_unit_id;
    logic a_pkg_id;
    logic [3:0] a_fmt;
    logic a_decor;
    logic [511:0] a_planes;
    logic b_valid;
    logic b_ready;
    logic [UNIT_ID_W - 1:0] b_unit_id;
    logic b_pkg_id;
    logic [3:0] b_fmt;
    logic b_decor;
    logic [3:0][31:0] b_anchors;
    logic [511:0] b_deltas;
    logic c_valid;
    logic c_ready;
    logic [UNIT_ID_W - 1:0] c_unit_id;
    logic c_pkg_id;
    logic [3:0] c_fmt;
    logic c_decor;
    logic [3:0][31:0] c_anchors;
    logic [511:0] c_deltas;
    logic [3:0] c_strategy;
    logic [31:0][4:0] c_indexes;
    logic [9:0] c_logical_bits;
    logic d_valid;
    logic d_ready;
    logic [UNIT_ID_W - 1:0] d_unit_id;
    logic d_pkg_id;
    logic [3:0] d_fmt;
    logic d_decor;
    logic [3:0][31:0] d_anchors;
    logic [511:0] d_deltas;
    logic [3:0] d_strategy;
    logic [31:0][4:0] d_indexes;
    logic [9:0] d_logical_bits;
    udc_enc_decorrelate #(.UNIT_ID_W(UNIT_ID_W)) u_decor (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_unit_id(s_unit_id),
        .s_pkg_id(s_pkg_id),
        .s_fmt(s_fmt),
        .s_raw(s_raw),
        .m_valid(a_valid),
        .m_ready(a_ready),
        .m_unit_id(a_unit_id),
        .m_pkg_id(a_pkg_id),
        .m_fmt(a_fmt),
        .m_decor(a_decor),
        .m_planes(a_planes)
    );
    udc_enc_delta #(.UNIT_ID_W(UNIT_ID_W)) u_delta (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(a_valid),
        .s_ready(a_ready),
        .s_unit_id(a_unit_id),
        .s_pkg_id(a_pkg_id),
        .s_fmt(a_fmt),
        .s_decor(a_decor),
        .s_planes(a_planes),
        .m_valid(b_valid),
        .m_ready(b_ready),
        .m_unit_id(b_unit_id),
        .m_pkg_id(b_pkg_id),
        .m_fmt(b_fmt),
        .m_decor(b_decor),
        .m_anchors(b_anchors),
        .m_deltas(b_deltas)
    );
    udc_enc_index_sel #(.UNIT_ID_W(UNIT_ID_W)) u_index (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(b_valid),
        .s_ready(b_ready),
        .s_unit_id(b_unit_id),
        .s_pkg_id(b_pkg_id),
        .s_fmt(b_fmt),
        .s_decor(b_decor),
        .s_anchors(b_anchors),
        .s_deltas(b_deltas),
        .m_valid(c_valid),
        .m_ready(c_ready),
        .m_unit_id(c_unit_id),
        .m_pkg_id(c_pkg_id),
        .m_fmt(c_fmt),
        .m_decor(c_decor),
        .m_anchors(c_anchors),
        .m_deltas(c_deltas),
        .m_strategy(c_strategy),
        .m_indexes(c_indexes),
        .m_logical_bits(c_logical_bits)
    );
    udc_enc_candidate_sel #(.UNIT_ID_W(UNIT_ID_W)) u_select (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(c_valid),
        .s_ready(c_ready),
        .s_unit_id(c_unit_id),
        .s_pkg_id(c_pkg_id),
        .s_fmt(c_fmt),
        .s_decor(c_decor),
        .s_anchors(c_anchors),
        .s_deltas(c_deltas),
        .s_strategy(c_strategy),
        .s_indexes(c_indexes),
        .s_logical_bits(c_logical_bits),
        .m_valid(d_valid),
        .m_ready(d_ready),
        .m_unit_id(d_unit_id),
        .m_pkg_id(d_pkg_id),
        .m_fmt(d_fmt),
        .m_decor(d_decor),
        .m_anchors(d_anchors),
        .m_deltas(d_deltas),
        .m_strategy(d_strategy),
        .m_indexes(d_indexes),
        .m_logical_bits(d_logical_bits)
    );
    udc_enc_package #(.UNIT_ID_W(UNIT_ID_W)) u_package (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(d_valid),
        .s_ready(d_ready),
        .s_unit_id(d_unit_id),
        .s_pkg_id(d_pkg_id),
        .s_fmt(d_fmt),
        .s_decor(d_decor),
        .s_anchors(d_anchors),
        .s_deltas(d_deltas),
        .s_strategy(d_strategy),
        .s_indexes(d_indexes),
        .s_logical_bits(d_logical_bits),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_unit_id(m_unit_id),
        .m_pkg_id(m_pkg_id),
        .m_fmt(m_fmt),
        .m_size_bytes(m_size_bytes),
        .m_bits(m_bits),
        .m_error(m_error)
    );
endmodule : udc_dic_enc
`default_nettype wire
