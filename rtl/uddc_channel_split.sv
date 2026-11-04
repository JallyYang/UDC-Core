`ifndef UDDC_PARSE_OFFSET_REG
`define UDDC_PARSE_OFFSET_REG 1
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
        parameter bit OFFSET_REGISTERED = `UDDC_PARSE_OFFSET_REG,
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
    localparam int unsigned METADATA_BITS = UNIT_ID_W+1+1+768+10+10+4+1;
    localparam int unsigned HEADER_BITS = METADATA_BITS+10+4+1;
    localparam int unsigned WIDTH_BITS = 4*63*6;
    localparam int unsigned INDEX_RESULT_BITS = WIDTH_BITS+10+1;
    localparam int unsigned INDEX_BITS = METADATA_BITS+INDEX_RESULT_BITS;
    localparam int unsigned PREFIX_BITS = 4*64*10;
    localparam int unsigned OFFSET_BITS = INDEX_BITS+PREFIX_BITS;
    localparam int unsigned LAYOUT_RESULT_BITS = 4*10+4*10+4*63*10+7+1;
    localparam int unsigned LAYOUT_BITS = METADATA_BITS+WIDTH_BITS+LAYOUT_RESULT_BITS;
    localparam int unsigned PARSED_BITS = 4+1+128+512+7+1;

    function automatic logic [HEADER_BITS-1:0] parse_header();
        logic [UNIT_ID_W-1:0] result_unit_id;
        logic result_package_id;
        logic result_final_snapshot;
        logic [767:0] result_region;
        logic [9:0] result_region_bits;
        logic [9:0] result_available_bits;
        logic [9:0] result_cursor;
        logic [3:0] result_format_id;
        logic result_decor;
        logic [3:0] result_strategy;
        logic result_error;
        logic [767:0] field_value;
        int cursor;
        int available;
        bit bad;
        result_unit_id = '0;
        result_package_id = '0;
        result_final_snapshot = '0;
        result_region = '0;
        result_region_bits = '0;
        result_available_bits = '0;
        result_cursor = '0;
        result_format_id = '0;
        result_decor = '0;
        result_strategy = '0;
        result_error = '0;
        result_unit_id = s_unit_id;
        result_package_id = s_pkg_id;
        result_final_snapshot = s_final;
        result_region = s_region;
        result_region_bits = 10'(occupied_bytes(s_cbmd) * 8);
        available = int'(s_available_bytes) * 8;
        if (available > int'(result_region_bits)) available = int'(result_region_bits);
        result_available_bits = 10'(available);
        cursor = s_pkg_id ? int'(result_region_bits)-1 : 0;
        bad = s_cbmd < 1 || s_cbmd > 5;
        take_field(s_region,available,s_pkg_id,cursor,2,field_value,bad);
        if (field_value[1:0] != 0) bad = 1;
        take_field(s_region,available,s_pkg_id,cursor,4,field_value,bad);
        result_format_id = field_value[3:0];
        if (channels(result_format_id) == 0) bad = 1;
        take_field(s_region,available,s_pkg_id,cursor,1,field_value,bad);
        result_decor = field_value[0] && can_decor(result_format_id);
        for (int channel = 0; channel < 4; channel++) begin
            if (channel < channels(result_format_id)) begin
                take_field(s_region,available,s_pkg_id,cursor,1,field_value,bad);
                result_strategy[channel] = field_value[0];
            end
        end
        result_cursor = 10'(cursor);
        result_error = bad;
        return {
            result_unit_id,
            result_package_id,
            result_final_snapshot,
            result_region,
            result_region_bits,
            result_available_bits,
            result_cursor,
            result_format_id,
            result_decor,
            result_strategy,
            result_error
        };
    endfunction

    function automatic logic [INDEX_RESULT_BITS-1:0] parse_indexes(
        input logic header_package_id,
        input logic [767:0] header_region,
        input logic [9:0] header_available_bits,
        input logic [9:0] header_cursor,
        input logic [3:0] header_format_id,
        input logic [3:0] header_strategy,
        input logic header_error
    );
        logic [3:0][62:0][5:0] result_widths;
        logic [9:0] result_cursor;
        logic result_error;
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
        result_widths = '0;
        result_cursor = '0;
        result_error = '0;
        cursor = int'(header_cursor);
        bad = header_error;
        for (int channel = 0; channel < 4; channel++) begin
            if (!bad && channel < channels(header_format_id)) begin
                width = width_of(header_format_id,channel);
                sample_count = samples(header_format_id,channel);
                index_width = index_bits(width);
                index_count = header_strategy[channel] ? sample_count/2 : 1;
                take_field(header_region,int'(header_available_bits),header_package_id,
                    cursor,index_count*index_width,field_value,bad);
                for (int sample_index = 0; sample_index < 63; sample_index++) begin
                    if (!bad && sample_index < sample_count-1) begin
                        index_offset = (header_strategy[channel] ? sample_index/2 : 0)*index_width;
                        index_value = int'((field_value >> index_offset) & 768'((1 << index_width)-1));
                        delta_width = decode_width(index_value,width);
                        if (delta_width < 0) bad = 1;
                        else result_widths[channel][sample_index] = 6'(delta_width);
                    end
                end
            end
        end
        result_cursor = 10'(cursor);
        result_error = bad;
        return {result_widths,result_cursor,result_error};
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

    function automatic logic [3:0][63:0][9:0] calculate_partial_offsets(
        input logic [3:0][62:0][5:0] widths
    );
        logic [9:0] prefix [0:3][0:3][0:63];
        logic [3:0][63:0][9:0] result;
        for (int channel = 0; channel < 4; channel++) begin
            for (int sample_index = 0; sample_index < 64; sample_index++) begin
                prefix[0][channel][sample_index] = '0;
                if (sample_index < 63)
                    prefix[0][channel][sample_index] = 10'(widths[channel][sample_index]);
            end
        end
        // Distances 1, 2 and 4 form the first three combinational levels.
        for (int level = 0; level < 3; level++) begin
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
            for (int sample_index = 0; sample_index < 64; sample_index++)
                result[channel][sample_index] = prefix[3][channel][sample_index];
        end
        return result;
    endfunction

    function automatic logic [LAYOUT_RESULT_BITS-1:0] calculate_layout(
        input logic [3:0][63:0][9:0] arg_prefix_partial,
        input logic [3:0] arg_format_id,
        input logic arg_package_id,
        input logic [9:0] arg_region_bits,
        input logic [9:0] arg_available_bits,
        input logic [9:0] arg_cursor,
        input logic arg_error
    );
        logic [3:0][9:0] result_anchor_start;
        logic [3:0][9:0] result_delta_start;
        logic [3:0][62:0][9:0] result_delta_offset;
        logic [6:0] result_size_bytes;
        logic result_error;
        logic [9:0] prefix [0:3][0:3][0:63];
        int cursor;
        int total_width;
        int used_bits;
        bit bad;
        result_anchor_start = '0;
        result_delta_start = '0;
        result_delta_offset = '0;
        result_size_bytes = '0;
        result_error = '0;
        cursor = int'(arg_cursor);
        bad = arg_error;
        for (int channel = 0; channel < 4; channel++) begin
            for (int sample_index = 0; sample_index < 64; sample_index++)
                prefix[0][channel][sample_index] = arg_prefix_partial[channel][sample_index];
        end
        // Complete the remaining distances 8, 16 and 32 after OFFSET_REG.
        for (int level = 0; level < 3; level++) begin
            for (int channel = 0; channel < 4; channel++) begin
                for (int sample_index = 0; sample_index < 64; sample_index++) begin
                    prefix[level+1][channel][sample_index] = prefix[level][channel][sample_index];
                    if (sample_index >= (1 << (level+3)))
                        prefix[level+1][channel][sample_index] = prefix[level][channel][sample_index] +
                            prefix[level][channel][sample_index-(1 << (level+3))];
                end
            end
        end
        for (int channel = 0; channel < 4; channel++) begin
            if (channel < channels(arg_format_id)) begin
                reserve_field(int'(arg_available_bits),arg_package_id,
                    cursor,width_of(arg_format_id,channel),result_anchor_start[channel],bad);
            end
        end
        for (int channel = 0; channel < 4; channel++) begin
            if (channel < channels(arg_format_id)) begin
                total_width = int'(prefix[3][channel][63]);
                reserve_field(int'(arg_available_bits),arg_package_id,
                    cursor,total_width,result_delta_start[channel],bad);
                for (int sample_index = 1; sample_index < 63; sample_index++)
                    result_delta_offset[channel][sample_index] = prefix[3][channel][sample_index-1];
            end
        end
        used_bits = arg_package_id ? int'(arg_region_bits)-1-cursor : cursor;
        if (used_bits <= 0 || used_bits > int'(arg_region_bits)) bad = 1;
        result_size_bytes = 7'((used_bits+7)/8);
        result_error = bad;
        return {result_anchor_start,result_delta_start,result_delta_offset,result_size_bytes,result_error};
    endfunction

    function automatic logic [PARSED_BITS-1:0] extract_samples(
        input logic [767:0] arg_region,
        input logic [3:0] arg_format_id,
        input logic arg_decor,
        input logic [3:0][62:0][5:0] arg_widths,
        input logic [3:0][9:0] arg_anchor_start,
        input logic [3:0][9:0] arg_delta_start,
        input logic [3:0][62:0][9:0] arg_delta_offset,
        input logic [6:0] arg_size_bytes,
        input logic arg_error
    );
        logic [3:0] result_format_id;
        logic result_decor;
        logic [3:0][31:0] result_anchors;
        logic [511:0] result_deltas;
        logic [6:0] result_size_bytes;
        logic result_error;
        logic [31:0] value;
        int width;
        int delta_width;
        int position;
        int plane_start;
        result_format_id = '0;
        result_decor = '0;
        result_anchors = '0;
        result_deltas = '0;
        result_size_bytes = '0;
        result_error = '0;
        result_error = arg_error;
        if (!arg_error) begin
            result_format_id = arg_format_id;
            result_decor = arg_decor;
            result_size_bytes = arg_size_bytes;
            for (int channel = 0; channel < 4; channel++) begin
                if (channel < channels(result_format_id)) begin
                    width = width_of(result_format_id,channel);
                    plane_start = plane_base(result_format_id,channel);
                    result_anchors[channel] = 32'(arg_region >> arg_anchor_start[channel]) & mask_w(width);
                    for (int sample_index = 0; sample_index < 63; sample_index++) begin
                        if (sample_index < samples(result_format_id,channel)-1) begin
                            delta_width = int'(arg_widths[channel][sample_index]);
                            position = int'(arg_delta_start[channel]) + int'(arg_delta_offset[channel][sample_index]);
                            value = '0;
                            if (delta_width > 0) begin
                                value = 32'(arg_region >> position) & mask_w(delta_width);
                                value = $unsigned($signed(value << (32-delta_width)) >>> (32-delta_width));
                            end
                            result_deltas = set_sample(result_deltas,plane_start+(sample_index+1)*width,width,value);
                        end
                    end
                end
            end
        end
        return {result_format_id,result_decor,result_anchors,result_deltas,result_size_bytes,result_error};
    endfunction

    logic [UNIT_ID_W-1:0] header_unit_id;
    logic header_package_id;
    logic header_final_snapshot;
    logic [767:0] header_region;
    logic [9:0] header_region_bits;
    logic [9:0] header_available_bits;
    logic [9:0] header_cursor;
    logic [3:0] header_format_id;
    logic header_decor;
    logic [3:0] header_strategy;
    logic header_error;
    logic [3:0][62:0][5:0] index_next_widths;
    logic [9:0] index_next_cursor;
    logic index_next_error;
    logic [UNIT_ID_W-1:0] index_unit_id;
    logic index_package_id;
    logic index_final_snapshot;
    logic [767:0] index_region;
    logic [9:0] index_region_bits;
    logic [9:0] index_available_bits;
    logic [3:0] index_format_id;
    logic index_decor;
    logic [3:0][62:0][5:0] index_widths;
    logic [9:0] index_cursor;
    logic index_error;
    logic [3:0][63:0][9:0] offset_next_prefix_partial;
    logic [UNIT_ID_W-1:0] offset_unit_id;
    logic offset_package_id;
    logic offset_final_snapshot;
    logic [767:0] offset_region;
    logic [9:0] offset_region_bits;
    logic [9:0] offset_available_bits;
    logic [3:0] offset_format_id;
    logic offset_decor;
    logic [3:0][62:0][5:0] offset_widths;
    logic [9:0] offset_cursor;
    logic offset_error;
    logic [3:0][63:0][9:0] offset_prefix_partial;
    logic [3:0][9:0] layout_next_anchor_start;
    logic [3:0][9:0] layout_next_delta_start;
    logic [3:0][62:0][9:0] layout_next_delta_offset;
    logic [6:0] layout_next_size_bytes;
    logic layout_next_error;
    logic [UNIT_ID_W-1:0] layout_unit_id;
    logic layout_package_id;
    logic layout_final_snapshot;
    logic [767:0] layout_region;
    logic [9:0] layout_region_bits;
    logic [9:0] layout_available_bits;
    logic [3:0] layout_format_id;
    logic layout_decor;
    logic [3:0][62:0][5:0] layout_widths;
    logic [3:0][9:0] layout_anchor_start;
    logic [3:0][9:0] layout_delta_start;
    logic [3:0][62:0][9:0] layout_delta_offset;
    logic [6:0] layout_size_bytes;
    logic layout_error;
    logic [3:0] parsed_format_id;
    logic parsed_decor;
    logic [3:0][31:0] parsed_anchors;
    logic [511:0] parsed_deltas;
    logic [6:0] parsed_size_bytes;
    logic parsed_error;
    logic index_valid;
    logic index_ready;
    logic offset_valid;
    logic offset_ready;
    logic layout_valid;
    logic layout_ready;
    logic output_ready;
    logic emit_result;
    logic response_complete;
    localparam bit STREAMING = MERGE_PREFIXES &&
        (INDEX_REGISTERED || OFFSET_REGISTERED || LAYOUT_REGISTERED);
    localparam int unsigned PACKAGE_TAGS = 2 * (2**UNIT_ID_W);
    logic [PACKAGE_TAGS-1:0] result_sent;
    logic [UNIT_ID_W:0] response_tag;

    // Function return orders match the named concatenations below.
    assign {
        header_unit_id,
        header_package_id,
        header_final_snapshot,
        header_region,
        header_region_bits,
        header_available_bits,
        header_cursor,
        header_format_id,
        header_decor,
        header_strategy,
        header_error
    } = parse_header();
    assign {index_next_widths,index_next_cursor,index_next_error} =
        parse_indexes(header_package_id,header_region,header_available_bits,header_cursor,header_format_id,header_strategy,header_error);
    assign offset_next_prefix_partial = calculate_partial_offsets(index_widths);
    assign {
        layout_next_anchor_start,
        layout_next_delta_start,
        layout_next_delta_offset,
        layout_next_size_bytes,
        layout_next_error
    } =
        calculate_layout(offset_prefix_partial,offset_format_id,offset_package_id,offset_region_bits,offset_available_bits,offset_cursor,offset_error);
    assign {parsed_format_id,parsed_decor,parsed_anchors,parsed_deltas,parsed_size_bytes,parsed_error} =
        extract_samples(layout_region,layout_format_id,layout_decor,layout_widths,layout_anchor_start,layout_delta_start,layout_delta_offset,layout_size_bytes,layout_error);
    // Header parsing shares the index stage. The moved register now divides
    // the six offset-prefix levels into two groups of three.
    uddc_parse_stage #(.REGISTERED(INDEX_REGISTERED), .DATA_WIDTH(INDEX_BITS)) u_indexes (
        .clk(clk), .rst_n(rst_n), .s_valid(s_valid), .s_ready(s_ready),
        .s_data({
            header_unit_id,
            header_package_id,
            header_final_snapshot,
            header_region,
            header_region_bits,
            header_available_bits,
            header_format_id,
            header_decor,
            index_next_widths,
            index_next_cursor,
            index_next_error
        }),
        .m_valid(index_valid), .m_ready(index_ready), .m_data({
            index_unit_id,
            index_package_id,
            index_final_snapshot,
            index_region,
            index_region_bits,
            index_available_bits,
            index_format_id,
            index_decor,
            index_widths,
            index_cursor,
            index_error
        })
    );
    uddc_parse_stage #(.REGISTERED(OFFSET_REGISTERED), .DATA_WIDTH(OFFSET_BITS)) u_offsets (
        .clk(clk), .rst_n(rst_n), .s_valid(index_valid), .s_ready(index_ready),
        .s_data({
            index_unit_id,
            index_package_id,
            index_final_snapshot,
            index_region,
            index_region_bits,
            index_available_bits,
            index_format_id,
            index_decor,
            index_widths,
            index_cursor,
            index_error,
            offset_next_prefix_partial
        }),
        .m_valid(offset_valid), .m_ready(offset_ready), .m_data({
            offset_unit_id,
            offset_package_id,
            offset_final_snapshot,
            offset_region,
            offset_region_bits,
            offset_available_bits,
            offset_format_id,
            offset_decor,
            offset_widths,
            offset_cursor,
            offset_error,
            offset_prefix_partial
        })
    );
    uddc_parse_stage #(.REGISTERED(LAYOUT_REGISTERED), .DATA_WIDTH(LAYOUT_BITS)) u_layout (
        .clk(clk), .rst_n(rst_n), .s_valid(offset_valid), .s_ready(offset_ready),
        .s_data({
            offset_unit_id,
            offset_package_id,
            offset_final_snapshot,
            offset_region,
            offset_region_bits,
            offset_available_bits,
            offset_format_id,
            offset_decor,
            offset_widths,
            layout_next_anchor_start,
            layout_next_delta_start,
            layout_next_delta_offset,
            layout_next_size_bytes,
            layout_next_error
        }),
        .m_valid(layout_valid), .m_ready(layout_ready), .m_data({
            layout_unit_id,
            layout_package_id,
            layout_final_snapshot,
            layout_region,
            layout_region_bits,
            layout_available_bits,
            layout_format_id,
            layout_decor,
            layout_widths,
            layout_anchor_start,
            layout_delta_start,
            layout_delta_offset,
            layout_size_bytes,
            layout_error
        })
    );
    // Response and request handshakes can be on different cycles. done is
    // meaningful on s_response_valid; streaming dispatch advances separately.
    assign s_streaming = STREAMING;
    assign response_tag = {layout_unit_id,layout_package_id};
    assign response_complete = !parsed_error || layout_final_snapshot;
    assign emit_result = response_complete && !result_sent[response_tag];
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
                    if (layout_final_snapshot) result_sent[tag] <= 1'b0;
                    else if (emit_result) result_sent[tag] <= 1'b1;
                end
            end
        end
    end else begin : independent_snapshots
        assign result_sent = '0;
    end

    // Payload order (MSB to LSB) follows the named port concatenations.
    de_rs_reg #(.NORST(1), .PLD_W(UNIT_ID_W+1+4+1+128+512+7+1)) u_output_slice (
        .aclk_i(clk), .aresetn_i(rst_n),
        .valid_i(layout_valid && emit_result), .ready_o(output_ready),
        .ready_i(m_ready), .valid_o(m_valid),
        .payload_i({layout_unit_id, layout_package_id, parsed_format_id, parsed_decor, parsed_anchors, parsed_deltas, parsed_size_bytes, parsed_error}),
        .payload_o({m_unit_id, m_pkg_id, m_fmt, m_decor, m_anchors, m_deltas, m_size_bytes, m_error})
    );
endmodule : uddc_channel_split
