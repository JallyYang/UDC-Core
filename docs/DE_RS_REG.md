# de_rs_reg 握手打拍模块

[RTL](../rtl/de_rs_reg.v) 按提供的截图恢复。截图中间缺失的写指针更新和第0项有效位
复位部分，按读指针及第1项的对称关系补全。端口、参数、内部变量名和队列行为保持截图
含义；按仓库规则省略文件头注释，不加入 nettype 或 translate 指令。

## 变量与端口

| 名称 | 含义 |
| --- | --- |
| `aclk_i / aresetn_i` | 时钟 / 低有效异步复位 |
| `PLD_W` | 一项完整载荷的位数，默认256 |
| `NORST` | 默认1，仅数据不复位；设为0时，两项数据也异步清零。控制始终复位 |
| `valid_i / payload_i` | 上游提供的有效标志和载荷 |
| `ready_o` | 本模块反馈给上游的可接收信号 |
| `valid_o / payload_o` | 本模块提供给下游的有效标志和载荷 |
| `ready_i` | **下游**反馈的可接收信号，方向不要与 `ready_o` 混淆 |
| `fifo_valid_cnt` | 当前占用项数，合法值0、1、2 |
| `pipe_wr / pipe_rd` | 本拍实际入队 / 出队，分别等于两侧的 valid 与 ready 相与 |
| `oetf_pipe_wr / oetf_pipe_rd` | 下一次写入 / 当前队首的1bit指针，每次对应握手后翻转 |
| `oetf_pipe_avl[1:0]` | 两个物理存储项各自的有效位 |
| `oetf_pipe_data[1:0]` | 两项载荷存储，每项 `PLD_W` bit |

## 代码行为

```text
ready_o = fifo_valid_cnt < 2
pipe_wr = valid_i && ready_o
pipe_rd = valid_o && ready_i
valid_o = oetf_pipe_avl[oetf_pipe_rd]
payload_o = oetf_pipe_data[oetf_pipe_rd]
```

`ready_o` 只依赖本地计数寄存器，切断下游 ready 到上游 ready 的组合路径。
有效位和指针也只依赖寄存状态，输入数据不会零拍穿透到输出。

| 沿前占用 | 可以入队 | 可以出队 | 行为 |
| --- | --- | --- | --- |
| 0 | 是 | 否 | 有效输入在本沿写入，下一个沿最早被下游接收 |
| 1 | 是 | 是 | 可同时读旧项、写另一项，计数保持1，可持续每拍传输 |
| 2 | 否 | 是 | 即使下游本拍接收，也不放行本拍输入；出队后下一拍恢复 ready |

计数仅入队时加1，仅出队时减1，同时或均不握手时保持。两个指针分别在入队和
出队时翻转。单项有效位按写入优先、读取其次更新；合法队列状态下，同一个物理项
不会在同一拍同时读写。输出反压时读指针保持，队首数据不会被覆盖。

它是**两项缓存、最小一拍延迟**，不是两拍串行延迟，也不是允许满队列同拍替换的
单项弹性寄存器。满后恢复接收有一拍延后，但队列里仍有另一项供下游接收；两侧
持续有效且下游持续接收时可维持每拍一项。多级联用时，这不等于任意上游空拍或
任意模式切换都能保证输出不断。

所有连接模块共用复位，复位期间不进行有效传输。控制复位清空计数、指针和有效位。
`NORST=1` 按原图不对数据加复位条件，即使复位期间数据寄存器有写入，也没有有效项；
释放后必须先有新入队才能产生有效输出。无效载荷不作解释。核心实例统一使用
`NORST=1`，不在组合 ready/valid 上增加复位门控。

## 当前替换范围

各调用处保留独立命名字段，通过显式拼接连接公共载荷端口；拼接顺序即代码从左到右的
高位到低位顺序，两端一一对应。公共模块内部使用一条通用数据总线，不使用结构体。

| 调用位置 | 载荷 / 保留的运算状态 |
| --- | --- |
| `udc_enc_split` | 32B分发请求及unit_id/SOP/LAST；原始缓存、slot及调度保留 |
| `udc_clear_check` | 最后一拍产生的hit/index/unit_id；跨四拍匹配交集保留 |
| `udc_enc_stream` | 原来的两项最终候选FIFO；两种颜色候选的半包状态保留 |
| `udc_enc_package` | 组装后的544bit压缩包和编号、格式、尺寸、错误 |
| 独立 `udc_enc_decorrelate` | 原始/变换候选输出；变换待发标志及其数据、编号另行保存 |
| 独立 `udc_enc_delta` / `udc_enc_index_sel` | 差分 / 索引计算结果及完整关联字段 |
| 独立 `udc_enc_candidate_sel` | 最终候选输出；配对比较所需原始候选仍单独保存 |
| `uddc_dec_split` | 两项前缀快照，含768bit区域、编号、包号、CBMD、有效长度及final |
| `uddc_parse_stage` | 三个可选解析边界；开关关闭时仍组合直通 |
| `uddc_channel_split` | 固定解析结果队列；响应表示快照已消费，成功结果此时入队 |
| `uddc_delta_cal` | 距离1/2/4/8的四个计算级，每级各有两项结果缓存 |
| `uddc_correlation` | 输出寄存配置开启时使用；核心中的配置为组合旁路 |
| `uddc_reconstruct_pixel` / `uddc_clear_recon` | 像素重排后的半单元 / Clear恢复的完整单元及编号 |

`udc_enc_pk`、`uddc_package_out` 的 `UNIT_SLOTS` 项顺序队列和按slot缓存不改成两项：
它们负责单元生命周期、结果关联和按序输出。半包累积状态、位图、计数器和FSM也不作为
传输寄存器替换。可选解析边界及颜色恢复的组合配置保留，关闭时不实例化打拍模块。

流式解码调度在最终快照**进入本地两项队列**后推进包状态，pkg1最终快照入队后推进
单元调度。队列中的快照已经复制完整字段，可以随后由解析器消费；输入slot仍保留到
最终输出retire。单扇区在CTX同时提交完整pkg0快照后直接转PKG1。
全旁路模式仍等待解析响应，避免对同一包预发多个成功请求而重复输出。

两项容量改变反压传播和恢复行为，但不新增无阻塞流水级。无阻塞逐拍表见
[UDC](UDC_STREAMING.md)、[UDDC](UDDC_PARSER_PIPELINE.md)。面积、输出选择mux时序和
工艺频率需综合评估，不能只凭ready链被切断判断完整通路达标。

## 验证

```bash
bash tests/run_de_rs_reg.sh
bash tests/run_udc_legacy.sh
bash tests/run_udc_stream.sh
bash tests/run_uddc.sh
UDDC_PARSE_OFFSET_REG=0 UDDC_PARSE_INDEX_REG=0 UDDC_PARSE_LAYOUT_REG=0 bash tests/run_uddc.sh
bash tests/run_uddc_parser.sh
python3 tests/check_rtl_style.py
```

公共模块使用独立队列模型检查两个NORST选项、1/32/256/1024bit位宽、4万拍、空满边界、
满且出队时拒绝输入、持续同时读写、数据顺序、反压稳定、异步复位及ready组合隔离。
旧64B编码路径以 `eb71130` 为逐包参考，当前32B核心以 `b732757` 为整核参考；
解析器八组合和解码核心继续使用独立字段参考及定向周期验证。
