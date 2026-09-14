# FPGA UDP DAQ

无硬件 FPGA 采集数据经 UDP 打包发送系统。

## 项目目标

在没有开发板和真实 ADC 的条件下，使用可综合 SystemVerilog RTL 模拟采集数据，完成：

1. 产生 16-bit 递增采样数据；
2. 通过 FIFO 进行数据缓冲；
3. 将样本打包为固定格式的 UDP 数据帧；
4. 在软件端解析数据帧并校验样本连续性与校验字段；
5. 使用 cocotb、波形和 Vivado 报告验证功能、资源及基本时序表现。

## 系统模块图

```text
                       +----------------+
                       |   daq_ctrl     |
                       | 配置/状态寄存器 |
                       +-------+--------+
                               |
                               v
+----------------+     +-------+--------+     +----------------+
| sample_generator| --> |    sync_fifo   | --> |   packetizer   | --> UDP 帧输出
| 模拟 ADC 采样   |     | 数据缓冲/溢出  |     | 帧头/序号/校验 |
+----------------+     +----------------+     +--------+-------+
                                                        |
                                                        v
                                             +----------------------+
                                             | Python 参考模型/解析器 |
                                             | 连续性与 checksum 校验 |
                                             +----------------------+
```

## 目录

```text
rtl/      SystemVerilog RTL
tb/       cocotb 与其他 testbench
sim/      仿真脚本和波形
scripts/  数据生成、解析和性能统计
vivado/   综合、实现和时序约束脚本
docs/     规格、测试、分析报告和每日记录
pcb/      可选的 AD 概念性硬件资料
```

每日进度记录见 [`docs/daily_log.md`](docs/daily_log.md)。
当前规格见 [`docs/spec_v1.md`](docs/spec_v1.md)。
DAQ 帧格式见 [`docs/packet_format.md`](docs/packet_format.md)。

## Day 4 仿真命令

在 WSL Ubuntu 中执行：

```bash
bash sim/run_fifo_tb.sh
gtkwave sim/sync_fifo_tb.vcd
```

也可以从 Windows PowerShell 执行：

```powershell
wsl.exe -d Ubuntu-22.04 -- bash -lc "cd /mnt/d/mywork/fpga-udp-daq && bash sim/run_fifo_tb.sh"
```

Day 5 采样器 smoke test：

```bash
bash sim/run_sample_generator_tb.sh
```

Day 6 控制寄存器 smoke test：

```bash
bash sim/run_daq_ctrl_tb.sh
```

Day 8 packetizer smoke test：

```bash
bash sim/run_packetizer_tb.sh
```

Day 10 的 checksum 已包含在 packetizer smoke test 中，最后一个 payload 后会额外检查 XOR16 输出。

Day 11 cocotb FIFO 测试：

```bash
bash sim/run_fifo_cocotb.sh
```

该命令同时运行基础 FIFO 测试和 Day 12 随机 scoreboard 测试，后者执行 2,000 个确定性伪随机时钟周期，并主动覆盖空读、满写和并行读写。

Day 13 参考帧模型：

```bash
python3 scripts/reference_packet.py --self-test
python3 scripts/reference_packet.py --frame-seq 7 0x1234 0xabcd
```

Day 14 packetizer cocotb 覆盖测试：

```bash
bash sim/run_packetizer_cocotb.sh
python3 scripts/reference_packet.py --self-test
```

测试矩阵见 [`docs/testplan.md`](docs/testplan.md)。当前 packetizer 尚未输出帧头和 `frame_seq`，该项暂由参考模型验证，RTL 接口集成后补测。

Day 15 顶层集成测试：

```bash
bash sim/run_daq_top_cocotb.sh
```

Day 16 统计寄存器测试：

```bash
bash sim/run_daq_ctrl_tb.sh
bash sim/run_daq_top_cocotb.sh
```

Day 17 随机背压测试：

```bash
bash sim/run_backpressure_cocotb.sh
```

Day 18 CDC 设计说明见 [`docs/cdc_note.md`](docs/cdc_note.md)。本日不实现异步 FIFO。

Day 19 吞吐率分析：

```bash
python3 scripts/throughput_report.py --self-test
python3 scripts/throughput_report.py
```

Day 20 MTU/UDP payload 限制与带宽表：

```bash
python3 scripts/throughput_report.py --self-test
python3 scripts/throughput_report.py
```

默认按 Ethernet MTU 1500、IPv4 20 字节、UDP 8 字节计算，UDP payload 上限为
1472 字节。DAQ 应用帧还包含 16 字节帧头和 2 字节 checksum，因此 16-bit
样本的安全上限为 727 个/帧；`daq_ctrl` 会拒绝 728 及以上的配置。报告仍保留
736 个/帧作为越界对照项。详细表格见 [`docs/mtu_report.md`](docs/mtu_report.md)。

Day 21 仿真阶段集成报告：

报告见 [`docs/integration_report.md`](docs/integration_report.md)，包含系统框图、
主要模块波形、测试通过率和已知限制。本日验收标签为 `v0.2-sim`。

Day 22 Vivado RTL Project：

Vivado 工程脚本和操作说明见 [`vivado/README.md`](vivado/README.md) 与
[`vivado/create_project.tcl`](vivado/create_project.tcl)。本日只导入 5 个 RTL
源文件并设置 `daq_top` 为顶层；器件 part 需先从本机 Vivado 器件库查询，Day23
再添加 XDC 时钟约束。

Day 23 Vivado 时钟约束与综合：

使用 [`vivado/daq_top.xdc`](vivado/daq_top.xdc) 约束 `clk` 为 100 MHz，运行
[`vivado/run_synthesis.tcl`](vivado/run_synthesis.tcl) 生成资源利用率报告；结果
记录见 [`docs/resource_utilization_synth.md`](docs/resource_utilization_synth.md)。

Day 24 Vivado Implementation 与时序基线：

运行 [`vivado/run_implementation.tcl`](vivado/run_implementation.tcl) 到
`route_design`，记录 WNS、TNS、关键路径和实现后资源；摘要见
[`docs/timing_baseline.md`](docs/timing_baseline.md)。本日不生成 bitstream。

## 当前范围

项目先以仿真和 Vivado 分析为主，不要求真实 ADC、以太网 PHY、开发板或 PCB 打样。LiteX/LiteEth 与单板硬件属于后续可选扩展。

## 进度

- [x] Day 1：项目目录与总体目标
- [x] Day 2：WSL 工具链安装与版本检查
- [x] Day 3：参数化同步 FIFO RTL
- [x] Day 4：FIFO 最小 testbench 与 VCD 波形
- [x] Day 5：valid/ready 递增采样器
- [x] Day 6：自定义 DAQ 控制/状态寄存器接口
- [x] Day 7：v1 规格与异常处理策略
- [x] Day 8：固定长度 payload packetizer FSM
- [x] Day 9：DAQ UDP 应用帧格式
- [x] Day 10：packetizer XOR checksum
- [x] Day 11：cocotb FIFO 协程测试
- [x] Day 12：FIFO 随机读写与参考队列检查
- [x] Day 13：Python DAQ 帧参考模型
- [x] Day 14：packetizer cocotb 覆盖矩阵
- [x] Day 15：daq_top 单时钟链路集成
- [x] Day 16：样本/帧/溢出/checksum 错误统计寄存器
- [x] Day 17：随机 ready 背压与 FIFO 最大水位
- [x] Day 18：ADC 时钟域与系统时钟域 CDC 说明
- [x] Day 19：采样带宽、帧开销与有效数据率分析
- [x] Day 20：MTU/UDP payload 限制与包长—协议开销—有效带宽表
- [x] Day 21：仿真阶段集成报告与 `v0.2-sim` 标签
- [x] Day 22：Vivado RTL Project 创建脚本与源文件导入说明
- [x] Day 23：100 MHz XDC 时钟约束、Vivado Synthesis 与资源报告
- [x] Day 24：Implementation、WNS/TNS、关键路径与时序基线
- [ ] Day 25 及以后：RTL 时序优化与 PPA 对比
