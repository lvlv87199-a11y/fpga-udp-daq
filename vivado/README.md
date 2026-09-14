# Day 22 Vivado 工程

Day22 只建立 RTL Project、导入当前 RTL 并设置 `daq_top` 为顶层；不安装板卡
文件，也不在本日执行综合和实现。

## 1. 查询已安装器件

打开 Vivado Tcl Shell，进入项目目录后执行：

```tcl
cd D:/mywork/fpga-udp-daq
set argv [list --list *xc7a*]
set argc [llength $argv]
source vivado/create_project.tcl
```

也可以在 PowerShell 中执行：

```powershell
D:\apps\vivado\Vivado\2017.4\bin\vivado.bat -mode batch -source D:\mywork\fpga-udp-daq\vivado\create_project.tcl -tclargs --list "*xc7a*"
```

从输出中选择本机确实存在的 part。不要把下面的示例 part 当作已确认的器件：

```text
xc7a100tcsg324-1
```

## 2. 创建工程

将 `<installed_part>` 替换为上一步查询到的完整 part 名称：

```powershell
D:\apps\vivado\Vivado\2017.4\bin\vivado.bat -mode batch -source D:\mywork\fpga-udp-daq\vivado\create_project.tcl -tclargs <installed_part>
```

工程会生成在：

```text
D:\mywork\fpga-udp-daq\vivado\daq_top_project\fpga_udp_daq.xpr
```

导入的 RTL 是 `rtl/daq_ctrl.sv`、`sample_generator.sv`、`sync_fifo.sv`、
`packetizer.sv` 和 `daq_top.sv`，顶层设置为 `daq_top`。

本次 Day22 已使用并验证器件 `xc7a100tcsg324-1`，工程已经生成并通过 Vivado
批处理创建检查。

## 3. Day23 添加时钟约束并综合

`daq_top.xdc` 为顶层 `clk` 添加 100 MHz 约束：

```tcl
create_clock -name sys_clk -period 10.000 [get_ports clk]
```

已有工程可在 Vivado Tcl Shell 或批处理模式中加入约束：

```powershell
D:\apps\vivado\Vivado\2017.4\bin\vivado.bat -mode batch -nolog -nojournal -notrace -source D:\mywork\fpga-udp-daq\vivado\add_constraints.tcl
```

运行综合并生成资源利用率报告：

```powershell
D:\apps\vivado\Vivado\2017.4\bin\vivado.bat -mode batch -nolog -nojournal -notrace -source D:\mywork\fpga-udp-daq\vivado\run_synthesis.tcl
```

报告输出到 `vivado/reports/utilization_synth.rpt` 和
`vivado/reports/utilization_synth_flat.rpt`。本日只执行 Synthesis，Implementation
和 WNS/TNS 时序分析留到后续 Day24。

如果工程目录已经存在，脚本默认停止以避免覆盖；确认需要重建时才使用：

```powershell
... -tclargs <installed_part> --force
```

## 3. GUI 中确认

双击生成的 `.xpr`，在 Sources 面板确认：

1. 5 个 `.sv` 文件位于 Design Sources；
2. `daq_top` 显示为 Top Module；
3. Project Settings → General 中的 Part 与查询结果一致；
4. 本日不需要添加 XDC，Day23 再加入时钟约束。
