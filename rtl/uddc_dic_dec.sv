// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module uddc_dic_dec
    #(
        parameter int unsigned UNIT_ID_W = 4
    )
    (
        input logic clk,
        input logic rst_n,
        input logic s_valid,
        output logic s_ready,
        output logic s_done,
        input logic [UNIT_ID_W - 1:0] s_unit_id,
        input logic s_pkg_id,
        input logic [3:0] s_cbmd,
        input logic [767:0] s_region,
        input logic [6:0] s_available_bytes,
        input logic s_final,
        output logic m_valid,
        input logic m_ready,
        output logic [UNIT_ID_W - 1:0] m_unit_id,
        output logic m_pkg_id,
        output logic [3:0] m_fmt,
        output logic [511:0] m_raw,
        output logic [6:0] m_size_bytes,
        output logic m_error
    );
    logic a_valid;
    logic a_ready;
    logic [UNIT_ID_W - 1:0] a_unit_id;
    logic a_pkg_id;
    logic [3:0] a_fmt;
    logic a_decor;
    logic [3:0][31:0] a_anchors;
    logic [511:0] a_deltas;
    logic [6:0] a_size_bytes;
    logic a_error;
    logic b_valid;
    logic b_ready;
    logic [UNIT_ID_W - 1:0] b_unit_id;
    logic b_pkg_id;
    logic [3:0] b_fmt;
    logic b_decor;
    logic [511:0] b_planes;
    logic [6:0] b_size_bytes;
    logic b_error;
    logic c_valid;
    logic c_ready;
    logic [UNIT_ID_W - 1:0] c_unit_id;
    logic c_pkg_id;
    logic [3:0] c_fmt;
    logic c_decor;
    logic [511:0] c_planes;
    logic [6:0] c_size_bytes;
    logic c_error;
    uddc_channel_split #(.UNIT_ID_W(UNIT_ID_W)) u_parse (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_done(s_done),
        .s_unit_id(s_unit_id),
        .s_pkg_id(s_pkg_id),
        .s_cbmd(s_cbmd),
        .s_region(s_region),
        .s_available_bytes(s_available_bytes),
        .s_final(s_final),
        .m_valid(a_valid),
        .m_ready(a_ready),
        .m_unit_id(a_unit_id),
        .m_pkg_id(a_pkg_id),
        .m_fmt(a_fmt),
        .m_decor(a_decor),
        .m_anchors(a_anchors),
        .m_deltas(a_deltas),
        .m_size_bytes(a_size_bytes),
        .m_error(a_error)
    );
    uddc_delta_cal #(.UNIT_ID_W(UNIT_ID_W)) u_delta (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(a_valid),
        .s_ready(a_ready),
        .s_unit_id(a_unit_id),
        .s_pkg_id(a_pkg_id),
        .s_fmt(a_fmt),
        .s_decor(a_decor),
        .s_anchors(a_anchors),
        .s_deltas(a_deltas),
        .s_size_bytes(a_size_bytes),
        .s_error(a_error),
        .m_valid(b_valid),
        .m_ready(b_ready),
        .m_unit_id(b_unit_id),
        .m_pkg_id(b_pkg_id),
        .m_fmt(b_fmt),
        .m_decor(b_decor),
        .m_planes(b_planes),
        .m_size_bytes(b_size_bytes),
        .m_error(b_error)
    );
    uddc_correlation #(.UNIT_ID_W(UNIT_ID_W)) u_color (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(b_valid),
        .s_ready(b_ready),
        .s_unit_id(b_unit_id),
        .s_pkg_id(b_pkg_id),
        .s_fmt(b_fmt),
        .s_decor(b_decor),
        .s_planes(b_planes),
        .s_size_bytes(b_size_bytes),
        .s_error(b_error),
        .m_valid(c_valid),
        .m_ready(c_ready),
        .m_unit_id(c_unit_id),
        .m_pkg_id(c_pkg_id),
        .m_fmt(c_fmt),
        .m_decor(c_decor),
        .m_planes(c_planes),
        .m_size_bytes(c_size_bytes),
        .m_error(c_error)
    );
    uddc_reconstruct_pixel #(.UNIT_ID_W(UNIT_ID_W)) u_pixel (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(c_valid),
        .s_ready(c_ready),
        .s_unit_id(c_unit_id),
        .s_pkg_id(c_pkg_id),
        .s_fmt(c_fmt),
        .s_decor(c_decor),
        .s_planes(c_planes),
        .s_size_bytes(c_size_bytes),
        .s_error(c_error),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_unit_id(m_unit_id),
        .m_pkg_id(m_pkg_id),
        .m_fmt(m_fmt),
        .m_raw(m_raw),
        .m_size_bytes(m_size_bytes),
        .m_error(m_error)
    );
endmodule : uddc_dic_dec
`default_nettype wire
