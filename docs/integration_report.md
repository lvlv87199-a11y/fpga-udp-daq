# FPGA UDP DAQ 仿真阶段集成报告

## 1. 阶段结论

截至 Day 21，项目已经完成无硬件仿真阶段的核心采集通路：控制寄存器配置
采样器，采样数据进入同步 FIFO，再由 packetizer 输出固定长度 payload 和
XOR16 checksum。顶层 Cocotb 测试验证了配置、连续样本、packet 边界、统计
寄存器和随机输出背压。

本阶段的 RTL 仍是 UDP 发送路径中的采集与打包子系统，不是完整的 Ethernet
MAC/UDP 发射器。完整应用帧头、`frame_seq` 和 UDP/IP 头目前由 Python 参考模型
定义和验证，尚未全部接入 RTL 数据通路。

## 2. 系统框图

```text
                         +---------------------+
                         |      daq_ctrl       |
                         | enable/divider/len  |
                         | status/statistics   |
                         +----------+----------+
                                    |
                                    | control registers
                                    v
+------------------+       +------+-------+       +----------------------+
| sample_generator |       |  sync_fifo   |       |      packetizer       |
| 16-bit samples   |------>| sample queue |------>| fixed payload + XOR16 |
| valid/ready      |       | full/empty   |       | valid/ready/last       |
+------------------+       +------+-------+       +-----------+----------+
                                    |                          |
                                    | full/overflow/level      | payload/checksum
                                    +-------------> daq_ctrl   v
                                                   UDP sender (future)

                         +--------------------------+
                         | Python reference model   |
                         | DAQ1 header/seq/parser   |
                         | continuity/checksum      |
                         +--------------------------+
```

当前所有 RTL 模块使用同一个 `clk` 和同步低有效复位 `rst_n`。`daq_top` 已完成
`daq_ctrl -> sample_generator -> sync_fifo -> packetizer` 的单时钟连接。

## 3. 主要波形

当前仓库已有 3 份可以用 GTKWave 打开的 VCD 波形：

| 波形 | 关注内容 | 打开命令 |
|---|---|---|
| `sim/sync_fifo_tb.vcd` | 复位、空读、连续写满、overflow、FIFO 顺序读取 | `gtkwave sim/sync_fifo_tb.vcd` |
| `sim/sample_generator_tb.vcd` | `sample_valid/ready`、分频等待、递增数据和 enable | `gtkwave sim/sample_generator_tb.vcd` |
| `sim/packetizer_tb.vcd` | FIFO 同步读延迟、payload `valid/ready/last`、checksum 握手 | `gtkwave sim/packetizer_tb.vcd` |

推荐在 GTKWave 中重点加入：

- FIFO：`clk`、`rst_n`、`wr_en`、`rd_en`、`din`、`dout`、`full`、`empty`、`overflow`；
- 采样器：`enable`、`sample_valid`、`sample_ready`、`sample_data`、`sample_divider`；
- packetizer：`fifo_rd_en`、`fifo_empty`、`payload_valid`、`payload_ready`、
  `payload_data`、`payload_last`、`checksum_valid`、`checksum_ready`、
  `checksum_data`、`packet_done`。

顶层 `daq_top` 当前通过 Cocotb 观察和断言，没有单独生成统一 VCD；这不影响
本阶段功能验收，后续若需要分析完整端到端时序再补充统一波形。

## 4. 验证结果

### 4.1 自动化回归

| 验证类别 | 覆盖内容 | 结果 |
|---|---|---:|
| SystemVerilog smoke test | FIFO、sample_generator、daq_ctrl、packetizer | 4/4 PASS |
| Cocotb FIFO | 基础读写 + 2,000 周期随机 scoreboard | 2/2 PASS |
| Cocotb packetizer | 包长、顺序、last、背压、checksum、尾包等待 | 2/2 PASS |
| Cocotb daq_top | 寄存器配置、连续样本、两帧输出、统计寄存器 | 1/1 PASS |
| Cocotb backpressure | 64 样本、8 包、随机 ready、FIFO 最大水位 | 1/1 PASS |
| Python 参考帧模型 | DAQ1 帧构造、解析、字节序和 XOR16 | 1/1 PASS |
| 吞吐率/MTU 分析 | 256、512、727、736 样本/帧边界 | 1/1 PASS |
| Verilator lint | 顶层 RTL 语法和静态检查 | PASS |

关键顶层结果：`samples=16`、`frames=2`、`fifo_overflows=0`、
`checksum_errors=1`。随机背压结果：`samples=64`、`packets=8`、最大 FIFO 水位
为 8、payload 背压 46 次、checksum 背压 3 次、正常路径 overflow 为 0。

### 4.2 测试计划状态

| 范围 | 结果 |
|---|---:|
| P01–P08 | 8/8 PASS |
| P09 packetizer RTL 帧序号 | BLOCKED：当前 RTL 没有帧头/`frame_seq` 端口 |
| T01–T03 | 3/3 PASS |

因此，已实现并可执行的测试项通过率为 **11/11 = 100%**；按测试计划全部 12
行统计为 **11 PASS、1 BLOCKED**，没有 FAIL。P09 不是测试失败，而是接口尚未
实现，已在 [`docs/testplan.md`](testplan.md) 中保留说明。

## 5. 已知限制

1. `packetizer.sv` 当前只输出 payload 和 XOR16 checksum，尚未在 RTL 中生成
   16-byte DAQ 应用帧头和 `frame_seq`。
2. 尚未实现 UDP/IP 头、Ethernet MAC、PHY、真实网口发送和软件 UDP 接收程序。
3. 当前系统只有单时钟域；ADC 时钟与系统时钟不同的异步 FIFO 方案仅记录在
   [`docs/cdc_note.md`](cdc_note.md)，尚未实现。
4. 尚未运行 Vivado 综合、布局布线、资源利用率和时序分析；Day 22 起再进入
   Vivado 阶段。
5. XOR16 只是轻量级完整性检查，不能替代 CRC，也不能替代 UDP/IP 校验和。
6. MTU 分析按 IPv4、1500-byte Ethernet MTU 和 1472-byte UDP payload 计算，
   不包含 Ethernet FCS、前导码和帧间隙；实际网络还可能使用 VLAN、IPv6 或更
   小的路径 MTU。
7. 现有 VCD 是模块级波形；顶层结果通过 Cocotb 断言验证，尚无统一 `daq_top`
   VCD。

## 6. 阶段验收与后续

- Day 1–21 的仿真阶段文档、RTL、测试和性能分析已归档。
- 本阶段验收标签：`v0.2-sim`。
- 下一阶段从 Day 22 开始，进入 Vivado RTL Project、XDC 时钟约束、综合资源
  报告和实现时序分析。
