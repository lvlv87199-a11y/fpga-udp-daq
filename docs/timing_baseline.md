# Day 24 Vivado Implementation 与时序基线

## 1. 运行条件

| 项目 | 结果 |
|---|---|
| Vivado | 2017.4 64-bit |
| Part | `xc7a100tcsg324-1` |
| Top module | `daq_top` |
| Clock | `sys_clk`，100 MHz，10.000 ns |
| Implementation | `impl_1` 完成至 `route_design` |
| Bitstream | 本日未生成 |
| Route status | 0 failed nets，0 unrouted nets，0 partially routed nets |

原始报告：

- [`timing_summary_impl.rpt`](../vivado/reports/timing_summary_impl.rpt)
- [`timing_paths_impl.rpt`](../vivado/reports/timing_paths_impl.rpt)
- [`utilization_impl.rpt`](../vivado/reports/utilization_impl.rpt)
- [`clock_utilization_impl.rpt`](../vivado/reports/clock_utilization_impl.rpt)

## 2. setup/hold 基本概念

- setup slack 表示数据在下一个时钟沿到达前还剩多少时间；最差值是 WNS，所有
  负 setup slack 的总和是 TNS。
- hold slack 表示数据在当前时钟沿之后保持稳定所剩的裕量；最差值是 WHS，所有
  负 hold slack 的总和是 THS。
- slack 为正表示满足约束；WNS/WHS 越大，当前时序裕量越充足。

## 3. 时序结果

| 指标 | 结果 | 失败端点 | 结论 |
|---|---:|---:|---|
| Setup WNS | `+4.893 ns` | 0 | 通过 |
| Setup TNS | `0.000 ns` | 0 / 690 | 通过 |
| Hold WHS | `+0.081 ns` | 0 | 通过 |
| Hold THS | `0.000 ns` | 0 / 690 | 通过 |
| Pulse-width WPWS | `+3.750 ns` | 0 | 通过 |
| Pulse-width TPWS | `0.000 ns` | 0 / 371 | 通过 |

Vivado 报告显示所有当前用户指定时序约束均满足。这里的时序结论针对
`sys_clk` 的内部寄存器到寄存器路径；当前 XDC 尚未加入外部输入/输出 delay，
因此不能把本结果解释为完整板级 I/O 时序签核。

## 4. 最差路径

### 4.1 最差 setup 路径

```text
Source      : packetizer_i/packet_length_reg[6]/C
Destination : packetizer_i/payload_last_reg/D
Path group  : sys_clk
Path type   : Setup (Max at Slow Process Corner)
Requirement : 10.000 ns
Data delay  : 5.077 ns
Logic       : 2.805 ns
Route       : 2.272 ns
Logic level : 7
Slack       : +4.893 ns
```

该路径位于 packetizer 的包长计数/`payload_last` 组合判断，主要由 4 级
`CARRY4` 加若干 LUT 构成，是当前应关注的关键路径。

### 4.2 最差 hold 路径

```text
Source      : sample_generator_i/sample_data_reg[8]/C
Destination : fifo_i/mem_reg_0_15_6_11/RAMB/I
Path group  : sys_clk
Path type   : Hold (Min at Fast Process Corner)
Data delay  : 0.187 ns
Slack       : +0.081 ns
```

hold 裕量虽然为正但明显小于 setup 裕量；后续修改时需要避免只改善 setup 而
破坏 hold。

## 5. 实现后资源

以下数据来自 `utilization_impl.rpt`，器件总资源沿用
`xc7a100tcsg324-1` 的资源容量：

| 资源 | 使用量 | 可用量 | 使用率 |
|---|---:|---:|---:|
| Slice LUTs | 229 | 63,400 | 0.36% |
| Logic LUTs | 217 | 63,400 | 0.34% |
| LUTRAM | 12 | 19,000 | 0.06% |
| Slice Registers | 346 | 126,800 | 0.27% |
| Block RAM Tile | 0 | 135 | 0.00% |
| DSP | 0 | 240 | 0.00% |

实现后逻辑资源仍然很小；FIFO 继续使用 distributed RAM。Day23 综合值为
230 LUT/329 FF，实现后的 LUT 略有下降、FF 因实现阶段的寄存器保留/映射统计
变化为 346，后续 PPA 对比应固定工具版本、器件和约束后再比较。

## 6. 基线结论与限制

- 在当前 100 MHz 单时钟约束下，内部 setup/hold 均通过，当前没有必须修复的
  时序违例。
- 最差 setup 路径集中在 packetizer 的包边界判断；Day25 可以以此作为优化观察点，
  但本日不修改 RTL。
- 该设计仍未加入真实 ADC、UDP/IP/MAC、PHY 和板级 I/O 约束；本报告不能代表
  完整硬件系统的最终时序签核。

## 7. 可复现命令

```powershell
D:\apps\vivado\Vivado\2017.4\bin\vivado.bat -mode batch -nolog -nojournal -notrace -source D:\mywork\fpga-udp-daq\vivado\run_implementation.tcl
```
