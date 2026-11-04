# uddc_channel_split 模块详解

本文对应当前 [uddc_channel_split.sv](../rtl/uddc_channel_split.sv)，先解释变量，
再沿代码说明功能。三个可选弹性寄存点的实现见
[uddc_parse_stage.sv](../rtl/uddc_parse_stage.sv)，整机逐拍调度见
[UDDC 解析流水说明](UDDC_PARSER_PIPELINE.md)。

本模块将一份压缩数据快照解析成格式、锚点、展开后的差分和包尺寸。
预测差分累加由后级 `uddc_delta_cal` 执行。本模块没有解析状态机，不使用结构体；
它包含四段组合逻辑、三个独立可选寄存点，以及一个固定的结果寄存器。

## 1. 接口变量

### 1.1 输入快照

| 变量 | 含义 |
| --- | --- |
| `clk` | 工作时钟 |
| `rst_n` | 与上下游共用的低有效复位；复位期间不进行有效传输 |
| `s_valid` | 当前有一份有效快照 |
| `s_ready` | 当前能够接收这份快照 |
| `s_unit_id` | 所属的128B unit编号 |
| `s_pkg_id` | 包号，0为pkg0，1为pkg1；每包最终恢复64B |
| `s_cbmd` | 整个unit的压缩模式，决定区域占用32B、64B或96B |
| `s_region[767:0]` | 最多96B的压缩区域，包含两个包及填充 |
| `s_available_bytes` | 当前已经收到的有效字节数 |
| `s_final` | 整个压缩区域已收齐，该包不会再有更长快照 |

三个长度的含义不同：

```text
s_region 的容量         = 96B
s_available_bytes       = 当前快照实际有效的数据量
m_size_bytes            = 解析得到的某一个压缩包的字节数
```

例如CBMD5的输入连续到达时，pkg0可依次有以下快照：

| 快照 | s_available_bytes | s_final |
| --- | ---: | ---: |
| 第一份 | 32 | 0 |
| 第二份 | 64 | 0 |
| 第三份 | 96 | 1 |

每份快照包含到目前为止的完整前缀，字段位置保持不变。新快照不能修改之前已经有效的字节。

### 1.2 快照响应与解析结果

| 变量 | 含义 |
| --- | --- |
| `s_response_valid` | 一份快照本拍处理结束，包括不足而不产生结果的快照 |
| `s_done` | 当前快照解析成功，或final已到、可以结束并报告错误；只在响应有效时解释 |
| `s_streaming` | 静态配置，通知调度器是否采用连续前缀调度 |
| `m_valid / m_ready` | 解析结果的有效与接收握手 |
| `m_unit_id / m_pkg_id` | 结果所属的unit和包号，错误结果也保留正确编号 |
| `m_fmt` | 解析出的数据格式 |
| `m_decor` | 后级是否执行颜色恢复 |
| `m_anchors[3:0][31:0]` | 最多四个通道的锚点，每个最多32bit |
| `m_deltas[511:0]` | 按通道平面排列、扩展到通道位宽的差分 |
| `m_size_bytes` | 当前压缩包的字节数，按字节向上取整 |
| `m_error` | 当前包解析失败 |

快照有响应，不一定有解析结果。非最终数据不足快照会响应done=0，但不产生新的m_valid。
`m_deltas`仍是差分，不能直接作为恢复后的像素数据使用。

## 2. 参数、开关与内部变量

### 2.1 可选寄存点

| 宏 | 模块参数 | 默认值 | 寄存前的组合工作 |
| --- | --- | ---: | --- |
| `UDDC_PARSE_INDEX_REG` | `INDEX_REGISTERED` | 1 | 包头、格式、策略解析；索引提取与差分位宽解码 |
| `UDDC_PARSE_OFFSET_REG` | `OFFSET_REGISTERED` | 1 | 位宽前缀求和前三层，距离1、2、4 |
| `UDDC_PARSE_LAYOUT_REG` | `LAYOUT_REGISTERED` | 1 | 距离8、16、32；字段定位、尺寸和范围检查 |

宏设为0时，对应data、valid、ready组合直通。宏不定义时使用默认值1，关闭需要显式赋0。
原`UDDC_PARSE_HEADER_REG`和`HEADER_REGISTERED`已分别改名为OFFSET版本，
原包头后的寄存点移动到位宽前缀求和中间。

`UNIT_ID_W`默认4，规定编号宽度。`MERGE_PREFIXES`独立实例默认0；当前
[uddc_dic_dec](../rtl/uddc_dic_dec.sv)将它设为1。静态流式配置为：

```systemverilog
STREAMING = MERGE_PREFIXES &&
    (INDEX_REGISTERED || OFFSET_REGISTERED || LAYOUT_REGISTERED);
```

因此核心中任意解析寄存点开启，就启用连续前缀去重模式；三个全关则使用响应驱动的提前切包方式。

### 2.2 各阶段的变量命名

| 前缀或变量 | 含义 |
| --- | --- |
| `header_*` | 包头解析的组合结果，没有独立的包头寄存器 |
| `index_next_*` | INDEX寄存点前的组合结果 |
| `index_*` | INDEX寄存点输出，关闭该寄存点时为组合直通值 |
| `offset_next_prefix_partial` | 前三层位宽求和的组合结果 |
| `offset_*` | OFFSET寄存点输出 |
| `layout_next_*` | 后三层求和、字段定位和检查的组合结果 |
| `layout_*` | LAYOUT寄存点输出 |
| `parsed_*` | 样本提取后的组合结果，准备写入固定结果寄存器 |
| `m_*` | 固定结果寄存器输出 |

各阶段携带编号、包号、final、原始快照和必要的解析状态，保证数据与标签同步。

| 数据变量 | 含义 |
| --- | --- |
| `*_region_bits` | CBMD对应的完整区域长度，单位bit |
| `*_available_bits` | 当前允许读取的有效bit范围 |
| `*_cursor` | 下一个字段的读取位置 |
| `*_format_id` | 包内数据格式 |
| `header_strategy[c]` | 通道c的策略，0为global，1为pair |
| `index_widths[c][k]` | 通道c的第k个差分实际使用的编码位宽 |
| `offset_prefix_partial` | 完成前三层求和后的中间结果 |
| `layout_anchor_start[c]` | 通道c锚点的绝对起始bit |
| `layout_delta_start[c]` | 通道c差分字段的绝对起始bit |
| `layout_delta_offset[c][k]` | 第k个差分在该通道差分字段中的偏移 |
| `layout_size_bytes` | 当前包消耗的字节数 |
| `result_sent[tag]` | 该包是否已提前交付过结果 |

```systemverilog
logic [3:0][62:0][5:0] index_widths;
logic [3:0][63:0][9:0] offset_prefix_partial;
```

第一项表示4个通道、每通道最多63个差分，每个宽度用6bit保存，以表示0～32。
第二项为每个通道准备64个求和位置，每个10bit；前63个输入是差分位宽，最后一个补零。

`HEADER_BITS`、`INDEX_BITS`、`OFFSET_BITS`、`LAYOUT_BITS`等只计算内部拼接位宽，
不是包尺寸或slot数量。字段分别命名，跨函数返回值和弹性寄存器接口时才用显式拼接连接。

## 3. 格式辅助函数

| 函数 | 功能 |
| --- | --- |
| `channels(f)` | 格式f有几个通道 |
| `width_of(f,c)` | 通道c的原始样本位宽 |
| `samples(f,c)` | 一个64B包中该通道有多少样本 |
| `can_decor(f)` | 该格式是否支持颜色变换 |
| `plane_base(f,c)` | 通道c在输出差分平面中的起始位置 |
| `index_bits(w)` | 一个差分宽度索引占多少bit |
| `decode_width(ix,w)` | 将索引转换成实际差分编码位宽 |
| `mask_w(w)` | 生成低w位全1的32bit掩码，w=32时返回全1 |
| `set_sample(v,pos,w,x)` | 将x低w位写入512bit平面中指定位置 |
| `occupied_bytes(cbmd)` | 将CBMD转换成完整压缩区域占用字节数 |

当前格式对应关系：

| 格式 | 通道位宽 | 每通道样本数 |
| --- | --- | --- |
| 1 | 8 | 64 |
| 2 | 16 | 32 |
| 3 | 32 | 16 |
| 4 | 16/16/16/16 | 8/8/8/8 |
| 5 | 32/32/32/32 | 4/4/4/4 |
| 6 | 8/8 | 32/32 |
| 7 | 16/16 | 16/16 |
| 8 | 24/8 | 16/16 |
| 9 | 11/11/10 | 16/16/16 |
| 10 | 8/8/8/8 | 16/16/16/16 |
| 11 | 10/10/10/2 | 16/16/16/16 |
| 12 | 32/32 | 8/8 |
| 13 | 32/8/24 | 8/8/8 |
| 14 | 32/32/32 | 6/5/5 |

颜色变换只允许格式4、5、9、10、11；其他格式的decor位即使为1也会被屏蔽，不单独报错。

通道平面起点为：

```text
plane_base(c) = Σ 前面各通道的 位宽 × 样本数
```

例如格式10四个通道依次占据m_deltas的[127:0]、[255:128]、[383:256]和[511:384]。
这里是通道平面排列，后级才恢复为原始像素排列。

## 4. 位流读取与字段定位

### 4.1 take_field()

| 参数 | 含义 |
| --- | --- |
| `src` | 压缩区域 |
| `bound` | 当前允许读取的bit边界 |
| `reverse` | 是否从高端向低端推进 |
| `cursor` | 当前读取位置，函数会更新 |
| `count` | 字段长度 |
| `value` | 提取结果，低位对齐 |
| `bad` | 错误标志，发生错误后保持 |

字段最低位置为：

```systemverilog
low_bit = reverse ? cursor - count + 1 : cursor;
```

检查count合法、low_bit非负、`low_bit+count<=bound`后，读取：

```systemverilog
value[b] = src[low_bit + b];
cursor += reverse ? -count : count;
```

pkg0从区域低端开始向上推进，pkg1从完整区域高端开始向下推进。
反转的是字段推进方向，字段内部bit顺序没有反转。

例如一次读取整个通道的索引字段，字段内部索引0仍在field_value低位；
整个通道的差分字段也是差分0位于字段低位。不能把pkg1理解为所有bit逐位倒序。

### 4.2 reserve_field()

该函数使用相同的游标和范围规则，只预留字段位置，不读取数据：

```text
检查字段范围
→ 返回字段最低bit
→ 推进cursor
```

它用来确定各通道锚点、差分字段的绝对位置。长度为0的差分字段可以合法存在。

## 5. 第一段：包头与索引

### 5.1 parse_header()

先确定完整区域及当前可用边界：

```text
region_bits    = occupied_bytes(s_cbmd) × 8
available_bits = min(s_available_bytes × 8, region_bits)
```

合法DIC模式：CBMD1为32B，CBMD2～4为64B，CBMD5为96B。
解析器只接受CBMD1～5；原始模式和Clear在核心中走旁路。

游标初值为：

```systemverilog
cursor = s_pkg_id ? region_bits - 1 : 0;
```

pkg1使用完整区域高端，不使用当前已收到数据的高端。96B区域只收到32B时，
不能把低32B的末尾当成pkg1包头，因此核心等完整区域到齐后才调度pkg1。

包头按顺序读取：

```text
2bit保留位，必须为0
4bit格式，必须有有效通道
1bit decor
每个有效通道各1bit策略
```

头部总长为`7+通道数`bit。格式0和15使解析失败。
读取结束后header_cursor指向索引字段，所有header_*仍是组合结果。

### 5.2 parse_indexes()

对每个通道确定原样本位宽、样本数、索引位宽和索引数量。

```systemverilog
index_bits(w) = w == 32 ? 5 : (w >= 16 ? 4 : 3);
index_count = strategy ? sample_count / 2 : 1;
```

| 策略 | 含义 |
| --- | --- |
| global，0 | 整个通道所有差分共用一个位宽索引 |
| pair，1 | 每两个差分共用一个位宽索引，末组允许只有一个差分 |

16个样本有一个锚点、15个差分。global用1个索引；pair用8个索引，分别控制
差分0/1、2/3……12/13和最后的差分14。

索引不是实际位宽：

```text
索引0               → 位宽0，差分值为0
普通非零索引ix      → 位宽ix+1
全1索引             → 满足条件时表示完整通道位宽
解码后超过通道位宽  → 非法
```

8bit通道的对应关系是：

```text
索引：0  1  2  3  4  5  6  7
位宽：0  2  3  4  5  6  7  8
```

24bit通道用4bit索引，索引15表示完整24bit，并不是16bit。

每个差分的实际位宽写入`index_next_widths[channel][sample_index]`。
`sample_index=0`对应锚点之后的第一个差分，最多63个，未使用位置保持0。

INDEX寄存点保存原始快照、编号、final、格式/decor、有效边界、差分位宽、
索引结束位置及错误状态。原始快照随流水携带，供最后一段提取数值。

## 6. 第二段：位宽前缀求和前三层

`calculate_partial_offsets()`计算差分编码位置所需的前缀和。

例如某通道的差分位宽为：

```text
位宽： [2, 3, 0, 4]
偏移： [0, 2, 5, 5]
总长： 9bit
```

内部先计算包含当前位置的前缀和：

```text
prefix[k] = w[0]+w[1]+...+w[k]
```

通过逐层加倍的网络计算前三层，距离为1、2、4：

```systemverilog
prefix[level+1][k] = prefix[level][k] + prefix[level][k-distance];
```

每层读取上一层，层内各位置可以并行。前三层结果经过OFFSET寄存点。
这一拍由原来的包头后寄存点迁移而来。

这里累加的是编码位宽，用于生成bit地址，不是对差分数值做恢复运算。

## 7. 第三段：后三层、定位及检查

`calculate_layout()`先完成距离8、16、32的后三层。加上前一段，总计六层：

```text
距离1/2/4 → OFFSET寄存点 → 距离8/16/32
```

每通道最多63个差分，加一个补零位置共64项，因此用六层覆盖整个通道。
完整前缀和生成后：

```text
第0个差分偏移 = 0
第k个差分偏移 = prefix[k-1]
通道差分总长   = prefix[63]
```

位流中各字段顺序为：

```text
包头
所有通道的索引
所有通道的锚点
通道0差分
通道1差分
...
```

因此先循环所有通道，用reserve_field()为每个锚点预留width_of()个bit；
再循环各通道，按其全部差分编码总长预留差分字段。
函数内部`prefix[3]`表示本段完成三层的结果，实际已包含前段的三层。

最终得到anchor_start、delta_start和delta_offset，包长由游标变化量决定：

```systemverilog
used_bits = pkg1 ? region_bits - 1 - cursor : cursor;
size_bytes = (used_bits + 7) / 8;
```

包长包含头、索引、锚点、差分，并向上取整到字节。这些结果经过LAYOUT寄存点。

## 8. 第四段：提取锚点和差分

`extract_samples()`按已计算的位置直接读取锚点：

```systemverilog
anchor = (region >> anchor_start[channel]) & mask_w(width);
```

差分绝对位置为：

```systemverilog
position = delta_start[channel] + delta_offset[channel][sample_index];
value = (region >> position) & mask_w(delta_width);
```

位宽为0时，差分直接取0；否则进行符号扩展：

```systemverilog
value = $unsigned($signed(value << (32-delta_width)) >>> (32-delta_width));
```

例如3bit的111表示-1，扩展得到32'hffffffff，写入8bit通道后为8'hff。
set_sample()只保存低width位，保持模2**width的补码语义。

差分写入位置为：

```systemverilog
plane_start + (sample_index + 1) * width
```

这里的加1保留每通道的样本位置0为0，后续位置依次保存差分0、1……。
锚点通过m_anchors单独输出。后级按格式规定的预测关系累加，再加锚点。

如果解析错误，parsed格式、decor、锚点、差分和尺寸全部为0，错误位保留为1。
是否交付这份错误结果还由final和去重状态决定。

## 9. 完整字段例子

以pkg0、格式3为例：单通道32bit、16个样本、global策略、宽度索引1，
因此有一个锚点和15个2bit差分。

| 字段 | bit位置 | 长度 |
| --- | --- | ---: |
| 保留位 | [1:0] | 2 |
| 格式 | [5:2] | 4 |
| decor | [6] | 1 |
| 策略 | [7] | 1 |
| 宽度索引 | [12:8] | 5 |
| 锚点 | [44:13] | 32 |
| 15个差分 | [74:45] | 30 |

共75bit，向上取整为10B。

```text
widths[0][0～14] = 2
delta_start[0] = 45
delta_offset[0] = 0
delta_offset[1] = 2
...
delta_offset[14] = 28
```

输出m_deltas[31:0]为0，[63:32]为第0个差分扩展到32bit，
依次到[511:480]保存第14个差分。地址先由位宽前缀和求出，再提取实际数值。

## 10. 响应、完成与去重

```systemverilog
response_complete = !parsed_error || layout_final_snapshot;
emit_result = response_complete && !result_sent[response_tag];
s_response_valid = layout_valid && layout_ready;
s_done = response_complete;
```

| 当前快照 | s_done | 新解析结果 |
| --- | ---: | --- |
| 成功，之前未交付 | 1 | 正常结果 |
| 非最终快照，数据不足或失败 | 0 | 无 |
| 最终失败，之前未交付 | 1 | error=1、载荷清零的结果 |
| 同一包已交付过结果 | 按当前解析是否完成决定 | 无，抑制重复 |

s_done只在s_response_valid有效时有意义，不直接对应当前输入请求。
本拍可能接收96B快照，同时响应较早的32B快照，不能将输入握手与当前s_done直接组合解释。

```systemverilog
response_tag = {layout_unit_id,layout_package_id};
```

默认UNIT_ID_W=4，共16种编号、每编号两个包，对应32个去重位。这些位不保存包数据。
更新优先级为：

```systemverilog
if (final_snapshot)
    result_sent[tag] <= 0;
else if (emit_result)
    result_sent[tag] <= 1;
```

第一次成功的非最终快照写入结果寄存器时置位，后续成功快照不重复输出；
最终快照消费后清除。最终快照首次成功时仍会输出结果，只是去重位保持0。
最终快照如果属于重复，也会清除去重位而不输出第二份结果。

因此流式输入必须发送最终快照，即使早期已成功。相同unit/pkg的各快照必须保持顺序，
并保证先前有效的字节不被后续快照改写。

流水模式的调度器以最终请求被接受推进pkg状态，不等待延后响应；全关配置才按有效响应
中的done决定重试或提前切包。相关逻辑见[uddc_dec_split.sv](../rtl/uddc_dec_split.sv)。

## 11. 反压与复位

每个开启的可选寄存级使用：

```systemverilog
s_ready = !m_valid || m_ready;
```

空寄存器可装入；旧结果本拍被接收时可同拍替换；满且后级不接收时保持。
寄存点关闭后data、valid向前组合传递，ready向后组合传递。

固定结果寄存器的控制为：

```systemverilog
output_ready = !m_valid || m_ready;
layout_ready = !emit_result || output_ready;
```

需要输出新结果的快照必须等待结果寄存器可接收；不足或重复前缀可以直接消费。
即使已有结果被下游反压，重复前缀也能继续通过，旧m_valid和载荷保持不变。
旧结果被接收而新快照不产生结果时，m_valid清零，载荷可以保留旧值但不再有效。

复位清除各级valid和去重状态，时序写入条件保护数据寄存器。
数据不要求全部清零，仅在valid有效时使用；组合逻辑不直接用rst_n屏蔽接口。

## 12. 单份快照的逐拍行为

以本模块输入请求握手的时钟沿为第0拍，三个寄存点全开、无反压：

| 时钟沿 | 当前快照处理 |
| --- | --- |
| 第0拍 | 包头与索引解析完成，写INDEX寄存器 |
| 第1拍 | 距离1/2/4求和，写OFFSET寄存器 |
| 第2拍 | 距离8/16/32、定位及检查，写LAYOUT寄存器 |
| 第3拍 | 提取样本，消费响应；需要输出时写固定结果寄存器 |
| 第4拍 | 下游最早在该沿接收结果 |

三个全关时，请求在第0拍直接写结果寄存器，下游最早第1拍接收。
有反压时各阶段可以停顿；不能把这些周期视为任意输入条件下的最大延迟承诺。

## 13. 首32B启动、连续快照重叠

以下以整个核心第一拍外部输入为T0，假设96B输入连续，pkg0需要64B快照才能完成：

| 时钟沿 | 解析流水工作 |
| --- | --- |
| T0 | 收到首32B，split寄存首份请求 |
| T1 | 32B包头/索引；输入累计64B |
| T2 | 32B前三层；64B包头/索引；输入累计96B |
| T3 | 32B后三层/定位；64B前三层；96B包头/索引；寄存pkg1请求 |
| T4 | 32B不足，响应done=0；64B后三层/定位；96B前三层；pkg1包头/索引 |
| T5 | 64B成功，输出pkg0解析结果并置去重位；96B后三层/定位；pkg1前三层 |
| T6 | 96B最终快照重复，不再输出并清除去重位；pkg1后三层/定位 |
| T7 | pkg1解析结果写入固定结果寄存器 |

随后pkg1通过差分恢复、颜色恢复和像素重排，当前默认配置整个unit在T13首拍输出。
T0起点与上一节不同，上一节第0拍是解析器请求握手，不是外部首拍输入。

当前每份快照独立解析：64B快照会重新解析自己的包头和索引，前一份快照的中间字段
不会并入它。时序利用来自快照连续进入、各阶段并行推进，以及首份成功结果提前交付。
pkg1从区域高端读取，仍要等完整区域到齐后调度。

## 14. 错误范围及维护要求

模块检查保留位、格式、宽度索引、字段边界和消耗长度。非最终失败前缀不输出错误，
最终失败且之前无成功结果时才交付一次错误结果。它不单独执行每包68B上限检查，
包间格式、尺寸及CBMD关系由[uddc_package_out.sv](../rtl/uddc_package_out.sv)检查。
本模块没有SOP/LAST接口，不执行外部帧格式校验，也没有CRC或padding一致性检查。

本说明随当前RTL维护，不固定为历史版本。下列变更必须在同一提交中更新本文及关联文档：

- 接口、参数、宏名、默认值或寄存边界改变。
- 字段读取顺序、索引规则、位置计算、错误处理或去重规则改变。
- ready/valid、响应、final清理、复位或slot复用约定改变。
- 功能变化导致单快照或整机逐拍表、延迟及测试条件改变。

修改时先核对变量含义，再更新行为、例子、逐拍表、测试入口和代码注释；
必须区分默认配置、全关配置与历史结果。规则见[AGENTS.md](../AGENTS.md)。
周期仿真与RTL结构分析不替代真实TSMC7工艺库下的综合和时序签核。
