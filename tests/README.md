# RTL 验证说明

所有构建产物保存在 checkout 外。需要 Python3、Verilator（可用 Python
`verilator` 包）和 C++20 编译器。风格检查另需 `pyslang==12.1.0`。
算法字段参考 [DicAlgo.html](../DicAlgo.html)，当前微架构见
[架构说明](../docs/ARCHITECTURE.md)。RTL 中的仿真断言已删除，以下检查由测试平台完成。

## 公共握手打拍与独立64B编码链

```bash
bash tests/run_de_rs_reg.sh
bash tests/run_udc_legacy.sh
```

`de_rs_reg_test` 用独立两项队列模型跑4万拍，覆盖NORST=0/1、1/32/256/1024bit，
检查空满边界、满且出队仍拒绝输入、同时读写、顺序、停顿稳定、复位和ready组合隔离。
`RS_TEST_BUILD_DIR`、`RS_TEST_JOBS` 控制构建目录和并行数。

`udc_legacy_compare` 将保留的独立64B `udc_dic_enc` 与 `eb71130` 比较1024个包，
覆盖14种格式、原始/颜色候选选择、标签、数据、尺寸、错误及独立输入空拍和输出反压。
`UDC_LEGACY_BUILD_DIR`、`UDC_TEST_JOBS` 控制构建；生成参考需要保留该提交历史。
公共模块的端口方向和替换位置见 [de_rs_reg说明](../docs/DE_RS_REG.md)。

## UDDC 核心

```bash
# 默认三个解析寄存点全开
bash tests/run_uddc.sh

# 三个寄存点全部组合旁路
UDDC_PARSE_OFFSET_REG=0 UDDC_PARSE_INDEX_REG=0 UDDC_PARSE_LAYOUT_REG=0 \
  bash tests/run_uddc.sh

# 独立解析器八种寄存组合
bash tests/run_uddc_parser.sh
```

`UDDC_PARSE_OFFSET_REG`、`UDDC_PARSE_INDEX_REG`、`UDDC_PARSE_LAYOUT_REG`
均为0/1，默认1，脚本将它们作为同名编译宏传入。开启一个或两个时仍检查功能并报告
周期；三个全开和全关的核心回归还检查下表中的延迟及空拍上限。
三个可选寄存点依次对应包头与索引解码后、偏移前三层后、偏移后三层及位置计算后。
包头后的独立寄存点已迁移到偏移计算中间；固定结果级始终保留。所有开启的边界及结果级使用两项 `de_rs_reg`，
最小延迟仍一拍，ready仅由本地占用决定。
原 `UDDC_PARSE_HEADER_REG` 已更名为 `UDDC_PARSE_OFFSET_REG`。

`UDDC_TEST_BUILD_DIR` 可复用构建目录，`UDDC_TEST_JOBS` 控制并行数（默认4）。
核心默认参数为8 slot，回归默认使用4 slot；可设 `UDDC_TEST_SLOTS=8` 验证另一配置。
`UDDC_PARSER_BUILD_DIR` 指定八组合测试的构建目录。

`uddc_generate.py` 生成908个确定性 unit，覆盖全部14种格式、全部CBMD模式、
符号差分、颜色恢复、保留位错误及两种包方向的 >64B 包。
`uddc_latency_vectors.py` 再生成1666个定向 unit，合计2574个、10296拍输出。
`uddc_decode.cpp` 检查数据、error、SOP/LAST、顺序及反压稳定性。
参考生成器描述字段布局与预测关系，是回归模型，不是独立规范认证。

## 请求、响应和去重

默认流水模式收到更多字节就提交更长快照，不等待上一响应。
96B unit 在输入连续且请求无反压时，独立调度测试要求：

| 周期（首拍输入T0） | 请求 |
| --- | --- |
| T1 | pkg0，32B快照 |
| T2 | pkg0，64B快照 |
| T3 | pkg0，96B最终快照 |
| T4 | pkg1，完整96B区域 |

调度测试在不提供任何响应的情况下也必须完成上述请求，防止重新引入串行等待。
反压时队首请求不变，第二项可以保存下一快照；队列满后停止入队，
恢复后可跳过未入队的过时前缀。调度器以最终快照入队推进流式状态，不等队首消费。全关配置则按有效响应的 done 决定提前切包；
例如96B、pkg0=40B时，它的请求周期为T1/32B、T2/64B、T3/pkg1。

`s_response_valid` 表示一份快照处理结束，`s_done` 仅在该响应有效时解释。
非最终不足前缀响应done=0、无数据输出；成功或最终错误响应done=1。
流水模式按 `{unit_id,pkg_id}` 抑制重复结果；即使提前成功，也必须提交最终快照清理状态。
当前没有保存前一份半包字段，每份更长快照独立解析。

`uddc_parser_compare.cpp` 对八种寄存组合分别比较3673份快照，以提交 `66e10f3`
的解析器为逐快照参考，再用测试端的去重模型确定应输出的结果。
检查字段、尺寸、tag、最终错误、重复成功抑制、final清理、tag重用、输入空拍及各配置
独立的随机输出反压。全关配置不启用流式去重，与旧独立快照接口一致。
参考源码由 `uddc_parser_reference.py` 提取到构建目录，需本地保留该提交历史。

`uddc_dispatch.cpp` 还检查输入转发、首拍 context 旁路、请求停顿稳定性，以及
slot 回收与新分配同拍发生时，新分配优先。输入slot复用和输出FIFO入队是两个不同接口；
当前输出FIFO满时仍不旁路同拍出队。

## 解码周期与连续性

以下首拍以第一拍输入握手T0为起点，假定无前序排队、输入连续、输出ready恒1。

| 工作负载 | 默认全开：首拍/末拍 | 全关：首拍/末拍 | 首拍后空拍 |
| --- | --- | --- | --- |
| 单扇区DIC，128 unit | T11/T14 | T8/T11 | 两配置均0 |
| 96B边界64B/20B，128 unit | T13/T16 | T9/T12 | 两配置均0 |
| 反向边界20B/64B，128 unit | T13/T16 | T9/T12 | 两配置均0 |
| 混合DIC，1025 unit | T13/T16（首unit） | T9/T12（首unit） | 两配置均0 |
| pkg0>64B，128 unit | T13/T16 | T10/T13 | 两配置均0 |
| 最终坏头，1 unit | T13/T16 | T10/T13 | 两配置均0 |
| Clear开头后接DIC，128 unit | T4/T7（Clear） | T4/T7（Clear） | 全开6，全关3 |

四级差分累加分别计算距离1、2、4、8；解析器的位置计算是六层前缀求和，默认以 OFFSET 寄存点分为3+3两拍，
不能计为六拍。核心中颜色恢复为组合模式，像素重排由一个输出寄存器捕获。
独立 `uddc_correlation` 的默认输出寄存选项仍为1。

`uddc_output_forward.cpp` 检查两种包到达顺序、最后包同拍转发首拍、停顿后由缓存保持、
错误包、格式不一致、非法尺寸和最终slot释放。最后一个包不需要先写缓存再等一拍输出。

目前没有统一预填充机制，连续DIC测试通过不表示任意模式切换也无空拍。
这些结果是周期行为，不是Fmax或面积结论；真实TSMC7、1.5GHz仍需工艺库和STA。

## UDC 分拍编码

```bash
bash tests/run_udc_stream.sh
```

默认测试包装器为4 slot。512个混合 unit 与固定 `b732757` 编码器逐拍比对，
覆盖格式0～15、尺寸限制、Clear、随机/结构化数据、独立输入间隔和输出反压、slot重用，
并检查反压稳定性。共比较1385拍输出；旧参考源码写入构建目录。
另有18组×128 unit，DIC使用全零数据，Clear使用固定模板；检查512拍输入均不反压、
T511接收最后一拍，启用DIC时首拍T9，limit=0时T7。

`UDC_TEST_BUILD_DIR`、`UDC_TEST_JOBS` 控制构建位置和并行数。
编码核心及独立64B测试在新版Verilator支持时关闭C++合并编译，降低单个编译进程的内存；
旧版工具自动沿用原有编译方式。内存受限时可设 `UDC_TEST_JOBS=1`。
这些测试验证兼容性与周期，不替代独立算法规范验证，详见
[UDC分拍编码](../docs/UDC_STREAMING.md)。

## 复位及RTL规范

两个核心驱动都运行 `core_reset_check.h`：在输入各个前缀之后，分别等待0/3/12拍，
保持输出反压并施加共用复位，再要求新原始unit正确输出、无旧结果和额外输出。
共12种编码场景、9种解码场景；解码测试用合法的早期pkg0头部覆盖去重位已置位后的复位。
复位期间不统计握手，ready/valid无须为0；控制保持时序复位。
公共打拍模块NORST=1的数据写入不加复位条件，无效数据由已复位的控制位隔离。

```bash
python3 tests/check_rtl_style.py
```

该脚本在预处理前拒绝 packed/unpacked/匿名结构体，包括未启用分支和未展开的宏，
并检查单变量声明、单目标always、
两套三段式FSM，以及全RTL语法和展开。Codex规则见 [AGENTS.md](../AGENTS.md)。
实际文件/always数量以脚本输出为准。规范见 [STYLE.md](../rtl/STYLE.md)。
