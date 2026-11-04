`ifndef UDDC_PARSE_HEADER_REG
`define UDDC_PARSE_HEADER_REG 1
`endif
`ifndef UDDC_PARSE_INDEX_REG
`define UDDC_PARSE_INDEX_REG 1
`endif
`ifndef UDDC_PARSE_LAYOUT_REG
`define UDDC_PARSE_LAYOUT_REG 1
`endif

module uddc_channel_split
    #(
        parameter int unsigned UNIT_ID_W = 4,
        parameter bit HEADER_REGISTERED = `UDDC_PARSE_HEADER_REG,
        parameter bit INDEX_REGISTERED = `UDDC_PARSE_INDEX_REG,
        parameter bit LAYOUT_REGISTERED = `UDDC_PARSE_LAYOUT_REG,
        parameter bit MERGE_PREFIXES = 1'b0
    )
    (
        input logic clk,
        input logic rst_n,
        input logic s_valid,
        output logic s_ready,
        output logic s_done,
        output logic s_response_valid,
        output logic s_streaming,
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
        output logic m_decor,
        output logic [3:0][31:0] m_anchors,
        output logic [511:0] m_deltas,
        output logic [6:0] m_size_bytes,
        output logic m_error
    );

    function automatic int channels(input logic [3:0] f);
        case (f)
            1, 2, 3: begin
                return 1;
            end
            6, 7, 8, 12: begin
                return 2;
            end
            9, 13, 14: begin
                return 3;
            end
            4, 5, 10, 11: begin
                return 4;
            end
            default: begin
                return 0;
            end
        endcase
    endfunction

    function automatic int width_of(
        input logic [3:0] f,
        input int c
    );
        if (c >= channels(f)) begin
            return 0;
        end
        case (f)
            1, 6, 10: begin
                return 8;
            end
            2, 4, 7: begin
                return 16;
            end
            3, 5, 12, 14: begin
                return 32;
            end
            8: begin
                return c == 0 ? 24 : 8;
            end
            9: begin
                return c == 2 ? 10 : 11;
            end
            11: begin
                return c == 3 ? 2 : 10;
            end
            13: begin
                case (c)
                    0: begin
                        return 32;
                    end
                    1: begin
                        return 8;
                    end
                    default: begin
                        return 24;
                    end
                endcase
            end
            default: begin
                return 0;
            end
        endcase
    endfunction

    function automatic int samples(
        input logic [3:0] f,
        input int c
    );
        if (c >= channels(f)) begin
            return 0;
        end
        case (f)
            1: begin
                return 64;
            end
            2, 6: begin
                return 32;
            end
            3, 7, 8, 9, 10, 11: begin
                return 16;
            end
            4, 12, 13: begin
                return 8;
            end
            5: begin
                return 4;
            end
            14: begin
                return c == 0 ? 6 : 5;
            end
            default: begin
                return 0;
            end
        endcase
    endfunction

    function automatic bit can_decor(input logic [3:0] f);
        return f == 4 || f == 5 || f == 9 || f == 10 || f == 11;
    endfunction

    function automatic int plane_base(
        input logic [3:0] f,
        input int c
    );
        int v;
        v = 0;
        for (int j = 0; j < 4; j++) begin
            if (j < c) begin
                v += width_of(f, j) * samples(f, j);
            end
        end
        return v;
    endfunction

    function automatic int index_bits(input int w);
        return w == 32 ? 5 : (w >= 16 ? 4 : 3);
    endfunction

    function automatic int decode_width(
        input int ix,
        input int w
    );
        int ib;
        int terminal;
        int dw;
        ib = index_bits(w);
        terminal = (1 << ib) - 1;
        dw = - 1;
        if (ix == 0) begin
            dw = 0;
        end
        else begin
            if (ix > 0 && ix < terminal) begin
                dw = ix + 1;
            end
            else begin
                if (ix == terminal && w > terminal) begin
                    dw = w;
                end
            end
        end
        if (dw > w) begin
            dw = - 1;
        end
        return dw;
    endfunction

    function automatic logic [31:0] mask_w(input int w);
        return w == 32 ? 32'hffffffff : ((32'h1 << w) - 1);
    endfunction

    function automatic logic [511:0] set_sample(
        input logic [511:0] v,
        input int pos,
        input int w,
        input logic [31:0] x
    );
        logic [511:0] r;
        // Only the low w bits are stored: modulo 2**w wrap is intentional.
        r = v;
        for (int b = 0; b < 32; b++)
        begin
            if (b < w && pos + b >= 0 && pos + b < 512) begin
                r[pos + b] = x[b];
            end
        end
        return r;
    endfunction

    function automatic int occupied_bytes(input logic [3:0] cbmd);
        case (cbmd)
            1: begin
                return 32;
            end
            2, 3, 4: begin
                return 64;
            end
            5: begin
                return 96;
            end
            0: begin
                return 128;
            end
            default: begin
                return 0;
            end
        endcase
    endfunction

    function automatic void take_field(
        input logic [767:0] src,
        input int bound,
        input bit reverse,
        inout int cursor,
        input int count,
        output logic [767:0] value,
        inout bit bad
    );
        int low_bit;
        value = '0;
        low_bit = reverse ? cursor - count + 1 : cursor;
        if (!bad) begin
            if (count < 0 || count > 768 || low_bit < 0 || low_bit + count > bound)
            begin
                bad = 1;
            end
            else begin
                for (int b = 0; b < 768; b++)
                begin
                    if (b < count) begin
                        value[b] = src[low_bit + b];
                    end
                end
                cursor += reverse ? - count : count;
            end
        end
    endfunction
    typedef struct packed {
        logic [UNIT_ID_W-1:0] unit_id;
        logic package_id;
        logic final_snapshot;
        logic [767:0] region;
        logic [9:0] region_bits;
        logic [9:0] available_bits;
        logic [9:0] cursor;
        logic [3:0] format_id;
        logic decor;
        logic [3:0] strategy;
        logic error;
    } header_t;
    typedef struct packed {
        header_t header;
        logic [3:0][62:0][5:0] widths;
        logic [9:0] cursor;
        logic error;
    } indexes_t;
    typedef struct packed {
        indexes_t indexes;
        logic [3:0][9:0] anchor_start;
        logic [3:0][9:0] delta_start;
        logic [3:0][62:0][9:0] delta_offset;
        logic [6:0] size_bytes;
        logic error;
    } layout_t;
    typedef struct packed {
        logic [3:0] format_id;
        logic decor;
        logic [3:0][31:0] anchors;
        logic [511:0] deltas;
        logic [6:0] size_bytes;
        logic error;
    } parsed_t;

    // Each snapshot is independent: a later prefix reparses its own data.
    function automatic header_t parse_header();
        header_t result;
        logic [767:0] field_value;
        int cursor;
        int available;
        bit bad;
        result = '0;
        result.unit_id = s_unit_id;
        result.package_id = s_pkg_id;
        result.final_snapshot = s_final;
        result.region = s_region;
        result.region_bits = 10'(occupied_bytes(s_cbmd) * 8);
        available = int'(s_available_bytes) * 8;
        if (available > int'(result.region_bits)) available = int'(result.region_bits);
        result.available_bits = 10'(available);
        cursor = s_pkg_id ? int'(result.region_bits)-1 : 0;
        bad = s_cbmd < 1 || s_cbmd > 5;
        take_field(s_region,available,s_pkg_id,cursor,2,field_value,bad);
        if (field_value[1:0] != 0) bad = 1;
        take_field(s_region,available,s_pkg_id,cursor,4,field_value,bad);
        result.format_id = field_value[3:0];
        if (channels(result.format_id) == 0) bad = 1;
        take_field(s_region,available,s_pkg_id,cursor,1,field_value,bad);
        result.decor = field_value[0] && can_decor(result.format_id);
        for (int channel = 0; channel < 4; channel++) begin
            if (channel < channels(result.format_id)) begin
                take_field(s_region,available,s_pkg_id,cursor,1,field_value,bad);
                result.strategy[channel] = field_value[0];
            end
        end
        result.cursor = 10'(cursor);
        result.error = bad;
        return result;
    endfunction

    function automatic indexes_t parse_indexes(input header_t header);
        indexes_t result;
        logic [767:0] field_value;
        int cursor;
        int width;
        int sample_count;
        int index_width;
        int index_count;
        int index_offset;
        int index_value;
        int delta_width;
        bit bad;
        result = '0;
        result.header = header;
        cursor = int'(header.cursor);
        bad = header.error;
        for (int channel = 0; channel < 4; channel++) begin
            if (!bad && channel < channels(header.format_id)) begin
                width = width_of(header.format_id,channel);
                sample_count = samples(header.format_id,channel);
                index_width = index_bits(width);
                index_count = header.strategy[channel] ? sample_count/2 : 1;
                take_field(header.region,int'(header.available_bits),header.package_id,
                    cursor,index_count*index_width,field_value,bad);
                for (int sample_index = 0; sample_index < 63; sample_index++) begin
                    if (!bad && sample_index < sample_count-1) begin
                        index_offset = (header.strategy[channel] ? sample_index/2 : 0)*index_width;
                        index_value = int'((field_value >> index_offset) & 768'((1 << index_width)-1));
                        delta_width = decode_width(index_value,width);
                        if (delta_width < 0) bad = 1;
                        else result.widths[channel][sample_index] = 6'(delta_width);
                    end
                end
            end
        end
        result.cursor = 10'(cursor);
        result.error = bad;
        return result;
    endfunction

    function automatic void reserve_field(
        input int available,
        input bit reverse,
        inout int cursor,
        input int count,
        output logic [9:0] start_bit,
        inout bit bad
    );
        int low_bit;
        low_bit = reverse ? cursor-count+1 : cursor;
        start_bit = '0;
        if (!bad) begin
            if (count < 0 || low_bit < 0 || low_bit+count > available) bad = 1;
            else begin
                start_bit = 10'(low_bit);
                cursor += reverse ? -count : count;
            end
        end
    endfunction

    function automatic layout_t calculate_layout(input indexes_t indexes);
        layout_t result;
        logic [9:0] prefix [0:6][0:3][0:63];
        int cursor;
        int sample_count;
        int total_width;
        int used_bits;
        bit bad;
        result = '0;
        result.indexes = indexes;
        cursor = int'(indexes.cursor);
        bad = indexes.error;
        // Six combinational prefix levels compute offsets and channel totals.
        for (int channel = 0; channel < 4; channel++) begin
            sample_count = samples(indexes.header.format_id,channel);
            for (int sample_index = 0; sample_index < 64; sample_index++) begin
                prefix[0][channel][sample_index] = '0;
                if (sample_index < 63 && sample_index < sample_count-1)
                    prefix[0][channel][sample_index] = 10'(indexes.widths[channel][sample_index]);
            end
        end
        for (int level = 0; level < 6; level++) begin
            for (int channel = 0; channel < 4; channel++) begin
                for (int sample_index = 0; sample_index < 64; sample_index++) begin
                    prefix[level+1][channel][sample_index] = prefix[level][channel][sample_index];
                    if (sample_index >= (1 << level))
                        prefix[level+1][channel][sample_index] = prefix[level][channel][sample_index] +
                            prefix[level][channel][sample_index-(1 << level)];
                end
            end
        end
        for (int channel = 0; channel < 4; channel++) begin
            if (channel < channels(indexes.header.format_id)) begin
                reserve_field(int'(indexes.header.available_bits),indexes.header.package_id,
                    cursor,width_of(indexes.header.format_id,channel),result.anchor_start[channel],bad);
            end
        end
        for (int channel = 0; channel < 4; channel++) begin
            if (channel < channels(indexes.header.format_id)) begin
                total_width = int'(prefix[6][channel][63]);
                reserve_field(int'(indexes.header.available_bits),indexes.header.package_id,
                    cursor,total_width,result.delta_start[channel],bad);
                for (int sample_index = 1; sample_index < 63; sample_index++)
                    result.delta_offset[channel][sample_index] = prefix[6][channel][sample_index-1];
            end
        end
        used_bits = indexes.header.package_id ? int'(indexes.header.region_bits)-1-cursor : cursor;
        if (used_bits <= 0 || used_bits > int'(indexes.header.region_bits)) bad = 1;
        result.size_bytes = 7'((used_bits+7)/8);
        result.error = bad;
        return result;
    endfunction

    function automatic parsed_t extract_samples(input layout_t layout);
        parsed_t result;
        logic [31:0] value;
        int width;
        int delta_width;
        int position;
        int plane_start;
        result = '0;
        result.error = layout.error;
        if (!layout.error) begin
            result.format_id = layout.indexes.header.format_id;
            result.decor = layout.indexes.header.decor;
            result.size_bytes = layout.size_bytes;
            for (int channel = 0; channel < 4; channel++) begin
                if (channel < channels(result.format_id)) begin
                    width = width_of(result.format_id,channel);
                    plane_start = plane_base(result.format_id,channel);
                    result.anchors[channel] = 32'(layout.indexes.header.region >> layout.anchor_start[channel]) & mask_w(width);
                    for (int sample_index = 0; sample_index < 63; sample_index++) begin
                        if (sample_index < samples(result.format_id,channel)-1) begin
                            delta_width = int'(layout.indexes.widths[channel][sample_index]);
                            position = int'(layout.delta_start[channel]) + int'(layout.delta_offset[channel][sample_index]);
                            value = '0;
                            if (delta_width > 0) begin
                                value = 32'(layout.indexes.header.region >> position) & mask_w(delta_width);
                                value = $unsigned($signed(value << (32-delta_width)) >>> (32-delta_width));
                            end
                            result.deltas = set_sample(result.deltas,plane_start+(sample_index+1)*width,width,value);
                        end
                    end
                end
            end
        end
        return result;
    endfunction

    header_t header_next;
    header_t header_data;
    indexes_t indexes_next;
    indexes_t indexes_data;
    layout_t layout_next;
    layout_t layout_data;
    parsed_t parsed;
    logic header_valid;
    logic header_ready;
    logic indexes_valid;
    logic indexes_ready;
    logic layout_valid;
    logic layout_ready;
    logic output_ready;
    logic emit_result;
    logic response_complete;
    localparam bit STREAMING = MERGE_PREFIXES &&
        (HEADER_REGISTERED || INDEX_REGISTERED || LAYOUT_REGISTERED);
    localparam int unsigned PACKAGE_TAGS = 2 * (2**UNIT_ID_W);
    logic [PACKAGE_TAGS-1:0] result_sent;
    logic [UNIT_ID_W:0] response_tag;

    assign header_next = parse_header();
    assign indexes_next = parse_indexes(header_data);
    assign layout_next = calculate_layout(indexes_data);
    assign parsed = extract_samples(layout_data);
    uddc_parse_stage #(.REGISTERED(HEADER_REGISTERED), .DATA_WIDTH($bits(header_t))) u_header (
        .clk(clk), .rst_n(rst_n), .s_valid(s_valid), .s_ready(s_ready), .s_data(header_next),
        .m_valid(header_valid), .m_ready(header_ready), .m_data(header_data)
    );
    uddc_parse_stage #(.REGISTERED(INDEX_REGISTERED), .DATA_WIDTH($bits(indexes_t))) u_indexes (
        .clk(clk), .rst_n(rst_n), .s_valid(header_valid), .s_ready(header_ready), .s_data(indexes_next),
        .m_valid(indexes_valid), .m_ready(indexes_ready), .m_data(indexes_data)
    );
    uddc_parse_stage #(.REGISTERED(LAYOUT_REGISTERED), .DATA_WIDTH($bits(layout_t))) u_layout (
        .clk(clk), .rst_n(rst_n), .s_valid(indexes_valid), .s_ready(indexes_ready), .s_data(layout_next),
        .m_valid(layout_valid), .m_ready(layout_ready), .m_data(layout_data)
    );
    // Response and request handshakes can be on different cycles. done is
    // meaningful on s_response_valid; streaming dispatch advances separately.
    assign s_streaming = STREAMING;
    assign response_tag = {layout_data.indexes.header.unit_id,layout_data.indexes.header.package_id};
    assign response_complete = !parsed.error || layout_data.indexes.header.final_snapshot;
    assign emit_result = response_complete && !result_sent[response_tag];
    assign output_ready = !m_valid || m_ready;
    assign layout_ready = !emit_result || output_ready;
    assign s_response_valid = layout_valid && layout_ready;
    assign s_done = response_complete;
    // Streaming sources must send a final snapshot even after early success.
    // Its consumption clears suppression before the slot can be reused.
    if (STREAMING) begin : suppress_repeated_prefixes
        for (genvar tag = 0; tag < PACKAGE_TAGS; tag++) begin : package_tag
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) result_sent[tag] <= 1'b0;
                else if (s_response_valid && response_tag == (UNIT_ID_W+1)'(tag)) begin
                    if (layout_data.indexes.header.final_snapshot) result_sent[tag] <= 1'b0;
                    else if (emit_result) result_sent[tag] <= 1'b1;
                end
            end
        end
    end else begin : independent_snapshots
        assign result_sent = '0;
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) m_valid <= 1'b0;
        else if (output_ready) m_valid <= layout_valid && emit_result;
    end
    always_ff @(posedge clk) begin
        if (rst_n && s_response_valid && emit_result) m_unit_id <= layout_data.indexes.header.unit_id;
    end
    always_ff @(posedge clk) begin
        if (rst_n && s_response_valid && emit_result) m_pkg_id <= layout_data.indexes.header.package_id;
    end
    always_ff @(posedge clk) begin
        if (rst_n && s_response_valid && emit_result) m_fmt <= parsed.format_id;
    end
    always_ff @(posedge clk) begin
        if (rst_n && s_response_valid && emit_result) m_decor <= parsed.decor;
    end
    always_ff @(posedge clk) begin
        if (rst_n && s_response_valid && emit_result) m_anchors <= parsed.anchors;
    end
    always_ff @(posedge clk) begin
        if (rst_n && s_response_valid && emit_result) m_deltas <= parsed.deltas;
    end
    always_ff @(posedge clk) begin
        if (rst_n && s_response_valid && emit_result) m_size_bytes <= parsed.size_bytes;
    end
    always_ff @(posedge clk) begin
        if (rst_n && s_response_valid && emit_result) m_error <= parsed.error;
    end
endmodule : uddc_channel_split
