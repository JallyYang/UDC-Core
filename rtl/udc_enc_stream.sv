module udc_enc_stream #(parameter int unsigned UNIT_ID_W = 4) (
    input logic clk,
    input logic rst_n,
    input logic s_valid,
    output logic s_ready,
    input logic [255:0] s_data,
    input logic s_sop,
    input logic s_last,
    input logic [UNIT_ID_W-1:0] s_unit_id,
    input logic [3:0] s_fmt,
    input logic s_enable,
    output logic m_valid,
    input logic m_ready,
    output logic [UNIT_ID_W-1:0] m_unit_id,
    output logic m_pkg_id,
    output logic [3:0] m_fmt,
    output logic [6:0] m_size_bytes,
    output logic [543:0] m_bits,
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
    function automatic int pair_base(
        input logic [3:0] f,
        input int c
    );
        int v;
        v = 0;
        for (int j = 0; j < 4; j++) begin
            if (j < c) begin
                v += samples(f, j) / 2;
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
    function automatic logic [31:0] sample_at(
        input logic [511:0] v,
        input int pos,
        input int w
    );
        return 32'(v >> pos) & mask_w(w);
    endfunction
    function automatic int min_index(
        input logic [31:0] x,
        input int w
    );
        logic signed [31:0] sx;
        logic signed [31:0] narrowed;
        int answer;
        int dw;
        // Interpret the already wrapped w-bit residual as signed two's complement.
        sx = $signed(x << (32 - w)) >>> (32 - w);
        answer = - 1;
        for (int ix = 0; ix < 32; ix++) begin
            dw = decode_width(ix, w);
            narrowed = 0;
            if (dw > 0) begin
                narrowed = (sx <<< (32 - dw)) >>> (32 - dw);
            end
            if (answer < 0 && dw >= 0 &&
                ((dw == 0 && sx == 0) || (dw > 0 && narrowed == sx))) begin
                answer = ix;
            end
        end
        return answer;
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
    function automatic int row_width(input logic [3:0] f);
        case (f)
            1, 2, 6: begin
                return 8;
            end
            3, 4, 7, 8, 9, 10, 11, 12, 13: begin
                return 4;
            end
            5: begin
                return 2;
            end
            default: begin
                return 1;
            end
        endcase
    endfunction
    function automatic bit can_decor(input logic [3:0] f);
        return f == 4 || f == 5 || f == 9 || f == 10 || f == 11;
    endfunction
    function automatic logic [511:0] transpose_planes(
        input logic [511:0] v,
        input logic [3:0] f,
        input bit inverse
    );
        logic [511:0] r;
        int pixel_w;
        int offset;
        int w;
        int n;
        int pb;
        int raw_pos;
        r = '0;
        pixel_w = 0;
        for (int c = 0; c < 4; c++) begin
            pixel_w += width_of(f, c);
        end
        offset = 0;
        for (int c = 0; c < 4; c++) begin
            w = width_of(f, c);
            n = samples(f, c);
            pb = plane_base(f, c);
            for (int k = 0; k < 64; k++) begin
                if (k < n) begin
                    raw_pos = f == 14 ? (3 * k + c) * 32 : k * pixel_w + offset;
                    if (inverse) begin
                        r = set_sample(r, raw_pos, w, sample_at(v, pb + k * w, w));
                    end
                    else begin
                        r = set_sample(r, pb + k * w, w, sample_at(v, raw_pos, w));
                    end
                end
            end
            offset += w;
        end
        return r;
    endfunction
    function automatic logic [511:0] color_transform(
        input logic [511:0] v,
        input logic [3:0] f,
        input bit inverse
    );
        logic [511:0] r;
        logic [31:0] x;
        logic [31:0] green;
        logic [31:0] ref_value;
        int w;
        int n;
        int pos;
        r = v;
        x = 0;
        green = 0;
        ref_value = 0;
        w = 0;
        n = 0;
        pos = 0;
        if (can_decor(f)) begin
            for (int c = 0; c < 3; c++) begin
                if (c != 1) begin
                    w = width_of(f, c);
                    n = samples(f, c);
                    for (int k = 0; k < 16; k++) begin
                        if (k < n) begin
                            pos = plane_base(f, c) + k * w;
                            x = sample_at(v, pos, w);
                            green = sample_at(v, plane_base(f, 1) + k * width_of(f, 1), width_of(f, 1));
                            // Green is unsigned; profile 9 requires a logical shift.
                            ref_value = f == 9 && c == 2 ? green >> 1 : green;
                            r = set_sample(r, pos, w, inverse ? x + ref_value : x - ref_value);
                        end
                    end
                end
            end
        end
        return r;
    endfunction
    localparam int unsigned PARTIAL_BITS = 512+512+128+160+20;
    localparam int unsigned CANDIDATE_BITS = 512+128+160+4+10+1+4+1+UNIT_ID_W;
    function automatic logic [PARTIAL_BITS-1:0] analyze_half(
        input logic [255:0] data,
        input logic [3:0] fmt,
        input logic second_half,
        input logic decor,
        input logic [511:0] previous_planes,
        input logic [511:0] previous_deltas,
        input logic [3:0][31:0] previous_anchors,
        input logic [31:0][4:0] previous_pairs,
        input logic [3:0][4:0] previous_global_indexes
    );
        logic [511:0] result_planes;
        logic [511:0] result_deltas;
        logic [3:0][31:0] result_anchors;
        logic [31:0][4:0] result_pairs;
        logic [3:0][4:0] result_global_indexes;
        logic [511:0] incoming;
        logic [511:0] planes;
        logic [31:0] residual;
        int pixel_width;
        int channel_offset;
        int width;
        int count_samples;
        int position;
        int parent;
        int base;
        int pair_position;
        int index_value;
        result_planes = second_half ? previous_planes : '0;
        result_deltas = second_half ? previous_deltas : '0;
        result_anchors = second_half ? previous_anchors : '0;
        result_pairs = second_half ? previous_pairs : '0;
        result_global_indexes = second_half ? previous_global_indexes : '0;
        incoming = transpose_planes(second_half ? {data,256'b0} : {256'b0,data},fmt,1'b0);
        planes = (second_half ? previous_planes : 512'b0) | incoming;
        // Retain original planes for boundary prediction; transform the complete
        // available pixel components before selecting this half's samples.
        result_planes = planes;
        if (decor) planes = color_transform(planes,fmt,1'b0);
        pixel_width = 0;
        for (int c=0;c<4;c++) pixel_width += width_of(fmt,c);
        channel_offset = 0;
        for (int c=0;c<4;c++) begin
            width = width_of(fmt,c);
            count_samples = samples(fmt,c);
            base = plane_base(fmt,c);
            for (int k=0;k<64;k++) begin
                position = fmt == 14 ? (3*k+c)*32 : k*pixel_width+channel_offset;
                if (k<count_samples && (position>=256)==second_half) begin
                    if (k==0) result_anchors[c] = sample_at(planes,base,width);
                    else begin
                        parent = fmt==14 || k%row_width(fmt)!=0 ? k-1 : k-row_width(fmt);
                        residual = (sample_at(planes,base+k*width,width)-sample_at(planes,base+parent*width,width)) & mask_w(width);
                        result_deltas = set_sample(result_deltas,base+k*width,width,residual);
                        index_value = min_index(residual,width);
                        pair_position = pair_base(fmt,c)+(k-1)/2;
                        if (index_value>int'(result_pairs[pair_position])) result_pairs[pair_position] = 5'(index_value);
                        if (index_value>int'(result_global_indexes[c])) result_global_indexes[c] = 5'(index_value);
                    end
                end
            end
            channel_offset += width;
        end
        return {result_planes,result_deltas,result_anchors,result_pairs,result_global_indexes};
    endfunction
    function automatic logic [CANDIDATE_BITS-1:0] select_strategy(
        input logic [511:0] partial_planes,
        input logic [511:0] partial_deltas,
        input logic [3:0][31:0] partial_anchors,
        input logic [31:0][4:0] partial_pairs,
        input logic [3:0][4:0] partial_global_indexes,
        input logic [3:0] fmt,
        input logic decor,
        input logic package_id,
        input logic [UNIT_ID_W-1:0] unit_id
    );
        logic [511:0] result_deltas;
        logic [3:0][31:0] result_anchors;
        logic [31:0][4:0] result_indexes;
        logic [3:0] result_strategy;
        logic [9:0] result_length;
        logic result_decor;
        logic [3:0] result_fmt;
        logic result_package_id;
        logic [UNIT_ID_W-1:0] result_unit_id;
        int width;
        int count_samples;
        int pair_count;
        int base;
        int global_cost;
        int pair_cost;
        int total;
        result_deltas = '0;
        result_anchors = '0;
        result_indexes = '0;
        result_strategy = '0;
        result_length = '0;
        result_decor = '0;
        result_fmt = '0;
        result_package_id = '0;
        result_unit_id = '0;
        result_deltas = partial_deltas;
        result_anchors = partial_anchors;
        result_fmt = fmt;
        result_decor = decor;
        result_package_id = package_id;
        result_unit_id = unit_id;
        total = 7;
        for (int c=0;c<4;c++) begin
            if (c<channels(fmt)) begin
                width = width_of(fmt,c);
                count_samples = samples(fmt,c);
                pair_count = count_samples/2;
                base = pair_base(fmt,c);
                global_cost = 1+index_bits(width)+(count_samples-1)*decode_width(int'(partial_global_indexes[c]),width);
                pair_cost = 1+pair_count*index_bits(width);
                for (int p=0;p<32;p++) begin
                    if (p<pair_count) pair_cost += decode_width(int'(partial_pairs[base+p]),width)*(2*p+2<count_samples ? 2 : 1);
                end
                if (pair_cost<global_cost) begin
                    result_strategy[c] = 1;
                    for (int p=0;p<32;p++) begin
                        if (p<pair_count) result_indexes[base+p] = partial_pairs[base+p];
                    end
                    total += width+pair_cost;
                end else begin
                    result_indexes[base] = partial_global_indexes[c];
                    total += width+global_cost;
                end
            end
        end
        result_length = 10'(total);
        return {
            result_deltas,
            result_anchors,
            result_indexes,
            result_strategy,
            result_length,
            result_decor,
            result_fmt,
            result_package_id,
            result_unit_id
        };
    endfunction
    logic [1:0] input_beat;
    logic input_accepted;
    logic [511:0] original_partial_planes;
    logic [511:0] original_partial_deltas;
    logic [3:0][31:0] original_partial_anchors;
    logic [31:0][4:0] original_partial_pairs;
    logic [3:0][4:0] original_partial_global_indexes;
    logic [511:0] color_partial_planes;
    logic [511:0] color_partial_deltas;
    logic [3:0][31:0] color_partial_anchors;
    logic [31:0][4:0] color_partial_pairs;
    logic [3:0][4:0] color_partial_global_indexes;
    logic [511:0] original_next_planes;
    logic [511:0] original_next_deltas;
    logic [3:0][31:0] original_next_anchors;
    logic [31:0][4:0] original_next_pairs;
    logic [3:0][4:0] original_next_global_indexes;
    logic [511:0] color_next_planes;
    logic [511:0] color_next_deltas;
    logic [3:0][31:0] color_next_anchors;
    logic [31:0][4:0] color_next_pairs;
    logic [3:0][4:0] color_next_global_indexes;
    logic [511:0] original_candidate_deltas;
    logic [3:0][31:0] original_candidate_anchors;
    logic [31:0][4:0] original_candidate_indexes;
    logic [3:0] original_candidate_strategy;
    logic [9:0] original_candidate_length;
    logic original_candidate_decor;
    logic [3:0] original_candidate_fmt;
    logic original_candidate_package_id;
    logic [UNIT_ID_W-1:0] original_candidate_unit_id;
    logic [511:0] color_candidate_deltas;
    logic [3:0][31:0] color_candidate_anchors;
    logic [31:0][4:0] color_candidate_indexes;
    logic [3:0] color_candidate_strategy;
    logic [9:0] color_candidate_length;
    logic color_candidate_decor;
    logic [3:0] color_candidate_fmt;
    logic color_candidate_package_id;
    logic [UNIT_ID_W-1:0] color_candidate_unit_id;
    logic [511:0] selected_candidate_deltas;
    logic [3:0][31:0] selected_candidate_anchors;
    logic [31:0][4:0] selected_candidate_indexes;
    logic [3:0] selected_candidate_strategy;
    logic [9:0] selected_candidate_length;
    logic selected_candidate_decor;
    logic [3:0] selected_candidate_fmt;
    logic selected_candidate_package_id;
    logic [UNIT_ID_W-1:0] selected_candidate_unit_id;
    logic [511:0] candidate_deltas;
    logic [3:0][31:0] candidate_anchors;
    logic [31:0][4:0] candidate_indexes;
    logic [3:0] candidate_strategy;
    logic [9:0] candidate_length;
    logic candidate_decor;
    logic [3:0] candidate_fmt;
    logic candidate_package_id;
    logic [UNIT_ID_W-1:0] candidate_unit_id;

    logic candidate_queue_ready;
    logic candidate_valid;
    logic package_ready;
    logic select_color_candidate;
    // A first half only updates local state; it needs no candidate FIFO entry.
    assign s_ready = (!s_enable || !input_beat[0] || candidate_queue_ready);
    assign input_accepted = s_valid && s_ready;
    // Half-analysis result: planes, deltas, anchors, pairs, global_indexes.
    assign {
        original_next_planes,
        original_next_deltas,
        original_next_anchors,
        original_next_pairs,
        original_next_global_indexes
    } =
        analyze_half(s_data,s_fmt,input_beat[0],1'b0,original_partial_planes,original_partial_deltas,original_partial_anchors,original_partial_pairs,original_partial_global_indexes);
    // Half-analysis result: planes, deltas, anchors, pairs, global_indexes.
    assign {color_next_planes,color_next_deltas,color_next_anchors,color_next_pairs,color_next_global_indexes} =
        analyze_half(s_data,s_fmt,input_beat[0],can_decor(s_fmt),color_partial_planes,color_partial_deltas,color_partial_anchors,color_partial_pairs,color_partial_global_indexes);
    // Candidate result: deltas, anchors, indexes, strategy, length, decor, fmt, package_id, unit_id.
    assign {
        original_candidate_deltas,
        original_candidate_anchors,
        original_candidate_indexes,
        original_candidate_strategy,
        original_candidate_length,
        original_candidate_decor,
        original_candidate_fmt,
        original_candidate_package_id,
        original_candidate_unit_id
    } =
        select_strategy(original_next_planes,original_next_deltas,original_next_anchors,original_next_pairs,original_next_global_indexes,s_fmt,1'b0,input_beat[1],s_unit_id);
    // Candidate result: deltas, anchors, indexes, strategy, length, decor, fmt, package_id, unit_id.
    assign {
        color_candidate_deltas,
        color_candidate_anchors,
        color_candidate_indexes,
        color_candidate_strategy,
        color_candidate_length,
        color_candidate_decor,
        color_candidate_fmt,
        color_candidate_package_id,
        color_candidate_unit_id
    } =
        select_strategy(color_next_planes,color_next_deltas,color_next_anchors,color_next_pairs,color_next_global_indexes,s_fmt,1'b1,input_beat[1],s_unit_id);
    assign select_color_candidate = can_decor(s_fmt) && color_candidate_length<original_candidate_length;
    assign selected_candidate_deltas = select_color_candidate ? color_candidate_deltas : original_candidate_deltas;
    assign selected_candidate_anchors = select_color_candidate ? color_candidate_anchors : original_candidate_anchors;
    assign selected_candidate_indexes = select_color_candidate ? color_candidate_indexes : original_candidate_indexes;
    assign selected_candidate_strategy = select_color_candidate ? color_candidate_strategy : original_candidate_strategy;
    assign selected_candidate_length = select_color_candidate ? color_candidate_length : original_candidate_length;
    assign selected_candidate_decor = select_color_candidate ? color_candidate_decor : original_candidate_decor;
    assign selected_candidate_fmt = select_color_candidate ? color_candidate_fmt : original_candidate_fmt;
    assign selected_candidate_package_id = select_color_candidate ? color_candidate_package_id : original_candidate_package_id;
    assign selected_candidate_unit_id = select_color_candidate ? color_candidate_unit_id : original_candidate_unit_id;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) input_beat <= 0;
        else if (input_accepted) input_beat <= input_beat+1'b1;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) original_partial_planes <= original_next_planes;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) original_partial_deltas <= original_next_deltas;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) original_partial_anchors <= original_next_anchors;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) original_partial_pairs <= original_next_pairs;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) original_partial_global_indexes <= original_next_global_indexes;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) color_partial_planes <= color_next_planes;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) color_partial_deltas <= color_next_deltas;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) color_partial_anchors <= color_next_anchors;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) color_partial_pairs <= color_next_pairs;
    end
    always_ff @(posedge clk) begin
        if (rst_n && input_accepted && s_enable) color_partial_global_indexes <= color_next_global_indexes;
    end

    // Payload order (MSB to LSB) follows the named port concatenations.
    de_rs_reg #(.NORST(1), .PLD_W(CANDIDATE_BITS)) u_candidate_slice (
        .aclk_i(clk), .aresetn_i(rst_n),
        .valid_i(s_valid && s_enable && input_beat[0]), .ready_o(candidate_queue_ready),
        .ready_i(package_ready), .valid_o(candidate_valid),
        .payload_i({selected_candidate_deltas, selected_candidate_anchors, selected_candidate_indexes, selected_candidate_strategy, selected_candidate_length, selected_candidate_decor, selected_candidate_fmt, selected_candidate_package_id, selected_candidate_unit_id}),
        .payload_o({candidate_deltas, candidate_anchors, candidate_indexes, candidate_strategy, candidate_length, candidate_decor, candidate_fmt, candidate_package_id, candidate_unit_id})
    );
    udc_enc_package #(.UNIT_ID_W(UNIT_ID_W)) u_package (
        .clk(clk), .rst_n(rst_n),
        .s_valid(candidate_valid), .s_ready(package_ready),
        .s_unit_id(candidate_unit_id), .s_pkg_id(candidate_package_id),
        .s_fmt(candidate_fmt), .s_decor(candidate_decor),
        .s_anchors(candidate_anchors), .s_deltas(candidate_deltas),
        .s_strategy(candidate_strategy), .s_indexes(candidate_indexes),
        .s_logical_bits(candidate_length),
        .m_valid(m_valid), .m_ready(m_ready), .m_unit_id(m_unit_id), .m_pkg_id(m_pkg_id),
        .m_fmt(m_fmt), .m_size_bytes(m_size_bytes), .m_bits(m_bits), .m_error(m_error)
    );
endmodule
