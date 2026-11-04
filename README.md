# UDC-Core

128B 数据单元的 UDC 压缩与 UDDC 解压 RTL，外部数据接口为 256bit（32B/拍）。
算法说明见 [DicAlgo.html](DicAlgo.html)。

| 入口 | 功能 | 输出与错误处理 |
| --- | --- | --- |
| [`udc_enc_core`](rtl/udc_enc_core.sv) | 原始数据 → Clear、DIC 或原始模式 | 压缩失败时回退原始模式；顶层没有错误输出。输入格式 0、15 当前映射为格式 10 |
| [`uddc_dec_core`](rtl/uddc_dec_core.sv) | Clear、DIC 或原始模式 → 128B 数据 | DIC 解析或包间校验失败时，输出四拍全零并置 `m_error=1` |

[微架构、接口、性能和错误处理说明](docs/ARCHITECTURE.md) 覆盖：

1. slot 缓存、顺序 FIFO、状态机和流水线寄存器。
2. 顶层及子模块间的接口、握手、反压和完成反馈。
3. TSMC7、1.5GHz 性能目标，以及当前 RTL 的周期延迟和吞吐验证范围。
4. 不支持格式时的实际行为。
5. 硬件错误、原始模式回退及接口协议要求。

设计时钟目标为 **TSMC7、1.5GHz（周期约 0.667ns）**。当前是功能 RTL 基线，
尚无完整核心在真实 TSMC7 工艺角下的时序签核结果。
[加法树实验](synthesis/adder_tree_compare/README.md) 使用 Nangate45 参考库，
不能据此认定 TSMC7 达标，也不能替代完整解码通路的 STA。

当前编码器采用 [32B 分拍编码路径](docs/UDC_STREAMING.md)，Clear 与 DIC 并行，
Clear 命中也等待已启动的两个 DIC 包处理完成。

当前解码器采用 [三个可选解析寄存点](docs/UDDC_PARSER_PIPELINE.md)，默认全开。
pkg0 从首拍 32B 启动，后续快照连续送入并去重；96B 定向案例 T13 首拍输出，
单扇区为 T11。全关时使用 T8～T10 的旁路配置，具体条件见流水说明。

复位约定：上下游及所有子模块共用 `rst_n`，复位期间不进行有效传输。
组合逻辑不直接使用复位信号屏蔽 ready/valid；复位期间即使信号为高也不计为握手。
时序逻辑负责清除状态和有效标志，事务从复位释放后的有效时钟沿开始。

验证入口：

```bash
# Python 3 + pyslang==12.1.0
python3 tests/check_rtl_style.py

# Python 3 + Verilator + C++20 编译器
bash tests/run_uddc.sh
bash tests/run_udc_stream.sh
bash tests/run_uddc_parser.sh
```

回归覆盖与逐拍性能条件见 [tests/README.md](tests/README.md)，
RTL 编写规范见 [rtl/STYLE.md](rtl/STYLE.md)。
