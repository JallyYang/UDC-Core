// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module udc_enc_core
    #(
        parameter int unsigned UNIT_ID_W = 4,
        parameter int unsigned UNIT_SLOTS = 8
    )
    (
        input logic clk,
        input logic rst_n,
        input logic s_valid,
        output logic s_ready,
        input logic [255:0] s_data,
        input logic s_sop,
        input logic s_last,
        input logic [3:0] s_udc_format,
        input logic [6:0] s_package_size_limit,
        input logic [9:0][127:0] cfg_clear_pattern,
        output logic m_valid,
        input logic m_ready,
        output logic [255:0] m_data,
        output logic m_sop,
        output logic m_last,
        output logic m_has_data,
        output logic [3:0] m_cbmd
    );
    logic clear_req_valid;
    logic clear_req_ready;
    logic [UNIT_ID_W - 1:0] clear_req_unit_id;
    logic clear_req_sop;
    logic clear_req_last;
    logic [255:0] clear_req_data;
    logic clear_rsp_valid;
    logic clear_rsp_ready;
    logic [UNIT_ID_W - 1:0] clear_rsp_unit_id;
    logic clear_rsp_hit;
    logic [3:0] clear_rsp_index;
    logic ctx_valid;
    logic ctx_ready;
    logic [UNIT_ID_W - 1:0] ctx_unit_id;
    logic [3:0] ctx_fmt;
    logic [6:0] ctx_limit_bytes;
    logic ctx_clear_hit;
    logic [3:0] ctx_clear_index;
    logic [1023:0] ctx_raw;
    logic req_valid;
    logic req_ready;
    logic [UNIT_ID_W - 1:0] req_unit_id;
    logic req_pkg_id;
    logic [3:0] req_fmt;
    logic [511:0] req_raw;
    logic retire_valid;
    logic [UNIT_ID_W - 1:0] retire_unit_id;
    logic result_valid;
    logic result_ready;
    logic [UNIT_ID_W - 1:0] result_unit_id;
    logic result_pkg_id;
    logic [3:0] result_fmt;
    logic [6:0] result_size_bytes;
    logic [543:0] result_bits;
    logic result_error;
    udc_enc_split #(.UNIT_ID_W(UNIT_ID_W), .UNIT_SLOTS(UNIT_SLOTS)) u_split (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data(s_data),
        .s_sop(s_sop),
        .s_last(s_last),
        .s_udc_format(s_udc_format),
        .s_package_size_limit(s_package_size_limit),
        .clear_req_valid(clear_req_valid),
        .clear_req_ready(clear_req_ready),
        .clear_req_unit_id(clear_req_unit_id),
        .clear_req_sop(clear_req_sop),
        .clear_req_last(clear_req_last),
        .clear_req_data(clear_req_data),
        .clear_rsp_valid(clear_rsp_valid),
        .clear_rsp_ready(clear_rsp_ready),
        .clear_rsp_unit_id(clear_rsp_unit_id),
        .clear_rsp_hit(clear_rsp_hit),
        .clear_rsp_index(clear_rsp_index),
        .ctx_valid(ctx_valid),
        .ctx_ready(ctx_ready),
        .ctx_unit_id(ctx_unit_id),
        .ctx_fmt(ctx_fmt),
        .ctx_limit_bytes(ctx_limit_bytes),
        .ctx_clear_hit(ctx_clear_hit),
        .ctx_clear_index(ctx_clear_index),
        .ctx_raw(ctx_raw),
        .pkg_valid(req_valid),
        .pkg_ready(req_ready),
        .pkg_unit_id(req_unit_id),
        .pkg_pkg_id(req_pkg_id),
        .pkg_fmt(req_fmt),
        .pkg_raw(req_raw),
        .retire_valid(retire_valid),
        .retire_unit_id(retire_unit_id)
    );
    udc_clear_check #(.UNIT_ID_W(UNIT_ID_W)) u_clear (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_clear_pattern(cfg_clear_pattern),
        .s_valid(clear_req_valid),
        .s_ready(clear_req_ready),
        .s_unit_id(clear_req_unit_id),
        .s_sop(clear_req_sop),
        .s_last(clear_req_last),
        .s_data(clear_req_data),
        .m_valid(clear_rsp_valid),
        .m_ready(clear_rsp_ready),
        .m_unit_id(clear_rsp_unit_id),
        .m_hit(clear_rsp_hit),
        .m_index(clear_rsp_index)
    );
    udc_dic_enc #(.UNIT_ID_W(UNIT_ID_W)) u_dic (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(req_valid),
        .s_ready(req_ready),
        .s_unit_id(req_unit_id),
        .s_pkg_id(req_pkg_id),
        .s_fmt(req_fmt),
        .s_raw(req_raw),
        .m_valid(result_valid),
        .m_ready(result_ready),
        .m_unit_id(result_unit_id),
        .m_pkg_id(result_pkg_id),
        .m_fmt(result_fmt),
        .m_size_bytes(result_size_bytes),
        .m_bits(result_bits),
        .m_error(result_error)
    );
    udc_enc_pk #(.UNIT_ID_W(UNIT_ID_W), .UNIT_SLOTS(UNIT_SLOTS)) u_pk (
        .clk(clk),
        .rst_n(rst_n),
        .ctx_valid(ctx_valid),
        .ctx_ready(ctx_ready),
        .ctx_unit_id(ctx_unit_id),
        .ctx_fmt(ctx_fmt),
        .ctx_limit_bytes(ctx_limit_bytes),
        .ctx_clear_hit(ctx_clear_hit),
        .ctx_clear_index(ctx_clear_index),
        .ctx_raw(ctx_raw),
        .pkg_valid(result_valid),
        .pkg_ready(result_ready),
        .pkg_unit_id(result_unit_id),
        .pkg_pkg_id(result_pkg_id),
        .pkg_fmt(result_fmt),
        .pkg_size_bytes(result_size_bytes),
        .pkg_bits(result_bits),
        .pkg_error(result_error),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data(m_data),
        .m_sop(m_sop),
        .m_last(m_last),
        .m_has_data(m_has_data),
        .m_cbmd(m_cbmd),
        .retire_valid(retire_valid),
        .retire_unit_id(retire_unit_id)
    );
endmodule : udc_enc_core
`default_nettype wire
