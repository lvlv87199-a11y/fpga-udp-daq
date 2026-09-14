# Day 23 Vivado 综合资源报告

## 1. 运行信息

| 项目 | 结果 |
|---|---|
| Vivado | 2017.4 64-bit |
| Part | `xc7a100tcsg324-1` |
| Top module | `daq_top` |
| Clock constraint | `sys_clk`，10.000 ns，100 MHz |
| Synthesis | 成功，0 errors，0 critical warnings |
| Implementation | Day24 已完成至 `route_design`，详见 [`timing_baseline.md`](timing_baseline.md) |

原始报告：

- [`utilization_synth.rpt`](../vivado/reports/utilization_synth.rpt)
- [`utilization_synth_flat.rpt`](../vivado/reports/utilization_synth_flat.rpt)

## 2. 资源摘要

| 资源 | 使用量 | 器件可用量 | 使用率 |
|---|---:|---:|---:|
| Slice LUTs | 230 | 63,400 | 0.36% |
| LUT as Logic | 218 | 63,400 | 0.34% |
| LUT as Memory | 12 | 19,000 | 0.06% |
| Slice Registers | 329 | 126,800 | 0.26% |
| Block RAM Tile | 0 | 135 | 0.00% |
| RAMB18 | 0 | 270 | 0.00% |
| DSPs | 0 | 240 | 0.00% |
| Bonded IOB | 121 | 210 | 57.62% |
| BUFGCTRL | 1 | 32 | 3.13% |

## 3. 结果解读

- 当前逻辑规模很小，LUT 和寄存器占用均低于 1%。
- `sync_fifo` 的 16×16 存储被推断为 distributed RAM（LUT memory），没有使用
  Block RAM；这是小深度 FIFO 的合理结果，后续可在更大深度下比较 BRAM 推断。
- IOB 使用率相对较高，主要因为当前 `daq_top` 将控制、状态、payload、checksum
  和调试观测信号全部暴露为顶层端口；接入实际 UDP/PHY 后需要重新定义封装接口。
- 报告中的 Slice LUT 数量是综合阶段结果，最终实现后可能因物理优化而变化。

## 4. 综合告警记录

本次综合没有错误或 critical warning，但有 72 条普通 warning，主要包括：

- `fifo_level[15:5]` 为了统一 16-bit 顶层观测接口而由常量 0 驱动；
- `ctrl_wdata[31:16]` 当前寄存器只使用低 16 bit，因此被报告为未连接/未使用；
- 统计计数器、FIFO `count` 等部分寄存器在当前顶层可观察路径下被综合优化提示；
- 小型 FIFO 使用 distributed RAM，而没有映射到 Block RAM。

这些告警没有阻止综合完成，但在后续 Day26 资源和时序分析中需要区分
“接口设计导致的提示”和真正的时序/功能问题。

## 5. 可复现命令

```powershell
D:\apps\vivado\Vivado\2017.4\bin\vivado.bat -mode batch -nolog -nojournal -notrace -source D:\mywork\fpga-udp-daq\vivado\run_synthesis.tcl
```

本日只完成综合和资源统计；WNS/TNS、关键路径和 Implementation 结果留到 Day24。
