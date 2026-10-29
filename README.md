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
5. 硬件错误、原始模式回退、仿真断言各自的触发条件。

设计时钟目标为 **TSMC7、1.5GHz（周期约 0.667ns）**。当前是功能 RTL 基线，
尚无完整核心在真实 TSMC7 工艺角下的时序签核结果。
[加法树实验](synthesis/adder_tree_compare/README.md) 使用 Nangate45 参考库，
不能据此认定 TSMC7 达标，也不能替代完整解码通路的 STA。

验证入口：

```bash
# Python 3 + pyslang==12.1.0
python3 tests/check_rtl_style.py

# Python 3 + Verilator + C++20 编译器
bash tests/run_uddc.sh
```

回归覆盖与逐拍性能条件见 [tests/README.md](tests/README.md)，
RTL 编写规范见 [rtl/STYLE.md](rtl/STYLE.md)。
