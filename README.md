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
- [ ] Day 12 及以后：随机测试、参考模型与 Vivado 分析
