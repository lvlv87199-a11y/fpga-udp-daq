---
name: fpga-udp-daq-project
description: 在 fpga-udp-daq 项目中协作构建无硬件 FPGA 采集数据经 UDP 打包发送系统，覆盖 RTL、仿真验证和 Vivado 分析。
---

# FPGA UDP DAQ 项目

## 任务介绍

围绕“模拟 ADC 数据 → FIFO 缓冲 → UDP 数据帧打包 → 软件解析校验”逐步完成项目。优先实现可综合的 SystemVerilog RTL、cocotb 自动化验证、波形与测试文档，再进行 Vivado 综合、时序和资源分析；LiteX、AD 原理图及真实硬件均属于可选扩展。

## 任务边界

- 所有项目文件限定在 `D:\mywork\fpga-udp-daq` 内，优先使用现有的 `rtl/`、`tb/`、`sim/`、`scripts/`、`vivado/`、`docs/` 和 `pcb/` 目录。
- 只围绕本项目的 RTL、仿真、验证、报告和必要脚本工作；不修改项目外文件、系统配置或无关仓库。
- 无硬件条件下以仿真和 Vivado 分析为主，不把真实 ADC、网口、LiteX 集成或 PCB 打样当作必需条件。
- 每次修改后说明变更内容，并在条件允许时运行相关仿真、脚本或静态检查。
