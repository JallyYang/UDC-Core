// Functional RTL baseline. See ../README.md for verification and timing limitations.
`default_nettype none

module uddc_dec_core
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
        input logic s_has_data,
        input logic [3:0] s_cbmd,
        input logic [9:0][127:0] cfg_clear_pattern,
        output logic m_valid,
        input logic m_ready,
        output logic [255:0] m_data,
        output logic m_sop,
        output logic m_last,
        output logic m_error
    );
    logic ctx_valid;
    logic ctx_ready;
    logic [UNIT_ID_W - 1:0] ctx_unit_id;
    logic [3:0] ctx_cbmd;
    logic [1023:0] ctx_raw;
    logic req_valid;
    logic req_ready;
    logic req_done;
    logic [UNIT_ID_W - 1:0] req_unit_id;
    logic req_pkg_id;
    logic [3:0] req_cbmd;
    logic [767:0] req_region;
    logic [6:0] req_available_bytes;
    logic req_final;
    logic clear_req_valid;
    logic clear_req_ready;
    logic [UNIT_ID_W - 1:0] clear_req_unit_id;
    logic [3:0] clear_req_index;
    logic retire_valid;
    logic [UNIT_ID_W - 1:0] retire_unit_id;
    logic clear_rsp_valid;
    logic clear_rsp_ready;
    logic [UNIT_ID_W - 1:0] clear_rsp_unit_id;
    logic [1023:0] clear_rsp_raw;
    logic result_valid;
    logic result_ready;
    logic [UNIT_ID_W - 1:0] result_unit_id;
    logic result_pkg_id;
    logic [3:0] result_fmt;
    logic [511:0] result_raw;
    logic [6:0] result_size_bytes;
    logic result_error;
    uddc_dec_split #(.UNIT_ID_W(UNIT_ID_W), .UNIT_SLOTS(UNIT_SLOTS)) u_split (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data(s_data),
        .s_sop(s_sop),
        .s_last(s_last),
        .s_has_data(s_has_data),
        .s_cbmd(s_cbmd),
        .ctx_valid(ctx_valid),
        .ctx_ready(ctx_ready),
        .ctx_unit_id(ctx_unit_id),
        .ctx_cbmd(ctx_cbmd),
        .ctx_raw(ctx_raw),
        .pkg_valid(req_valid),
        .pkg_ready(req_ready),
        .pkg_done(req_done),
        .pkg_unit_id(req_unit_id),
        .pkg_pkg_id(req_pkg_id),
        .pkg_cbmd(req_cbmd),
        .pkg_region(req_region),
        .pkg_available_bytes(req_available_bytes),
        .pkg_final(req_final),
        .clear_valid(clear_req_valid),
        .clear_ready(clear_req_ready),
        .clear_unit_id(clear_req_unit_id),
        .clear_index(clear_req_index),
        .retire_valid(retire_valid),
        .retire_unit_id(retire_unit_id)
    );
    uddc_clear_recon #(.UNIT_ID_W(UNIT_ID_W)) u_clear (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_clear_pattern(cfg_clear_pattern),
        .s_valid(clear_req_valid),
        .s_ready(clear_req_ready),
        .s_unit_id(clear_req_unit_id),
        .s_index(clear_req_index),
        .m_valid(clear_rsp_valid),
        .m_ready(clear_rsp_ready),
        .m_unit_id(clear_rsp_unit_id),
        .m_raw(clear_rsp_raw)
    );
    uddc_dic_dec #(.UNIT_ID_W(UNIT_ID_W)) u_dic (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(req_valid),
        .s_ready(req_ready),
        .s_done(req_done),
        .s_unit_id(req_unit_id),
        .s_pkg_id(req_pkg_id),
        .s_cbmd(req_cbmd),
        .s_region(req_region),
        .s_available_bytes(req_available_bytes),
        .s_final(req_final),
        .m_valid(result_valid),
        .m_ready(result_ready),
        .m_unit_id(result_unit_id),
        .m_pkg_id(result_pkg_id),
        .m_fmt(result_fmt),
        .m_raw(result_raw),
        .m_size_bytes(result_size_bytes),
        .m_error(result_error)
    );
    uddc_package_out #(.UNIT_ID_W(UNIT_ID_W), .UNIT_SLOTS(UNIT_SLOTS)) u_out (
        .clk(clk),
        .rst_n(rst_n),
        .ctx_valid(ctx_valid),
        .ctx_ready(ctx_ready),
        .ctx_unit_id(ctx_unit_id),
        .ctx_cbmd(ctx_cbmd),
        .ctx_raw(ctx_raw),
        .pkg_valid(result_valid),
        .pkg_ready(result_ready),
        .pkg_unit_id(result_unit_id),
        .pkg_pkg_id(result_pkg_id),
        .pkg_fmt(result_fmt),
        .pkg_raw(result_raw),
        .pkg_size_bytes(result_size_bytes),
        .pkg_error(result_error),
        .clear_valid(clear_rsp_valid),
        .clear_ready(clear_rsp_ready),
        .clear_unit_id(clear_rsp_unit_id),
        .clear_raw(clear_rsp_raw),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data(m_data),
        .m_sop(m_sop),
        .m_last(m_last),
        .m_error(m_error),
        .retire_valid(retire_valid),
        .retire_unit_id(retire_unit_id)
    );
endmodule : uddc_dec_core
`default_nettype wire
