# ADC 时钟域与系统时钟域的 CDC 说明

## 1. 当前假设

当前 `daq_top` 使用单一 `clk`，`sample_generator`、`sync_fifo`、`packetizer` 和 `daq_ctrl` 都在同一个时钟域。因此当前的 `sync_fifo` 不能直接连接一个独立时钟的真实 ADC。

如果 ADC 使用 `adc_clk`，而 packetizer/UDP 逻辑使用 `sys_clk`，不能只把 ADC 数据和 `valid` 信号直接接到系统域。多位数据总线可能在不同位上分别跨越不同周期，单比特控制信号也可能产生亚稳态、脉冲丢失或重复采样。

## 2. 推荐结构

```text
ADC domain (adc_clk)                         System domain (sys_clk)

ADC data/valid                               packetizer/read side
       |                                              ^
       v                                              |
+--------------------+       dual-clock       +--------------------+
| async FIFO write   | === dual-port memory == | async FIFO read    |
| wr_bin/wr_gray     |                         | rd_bin/rd_gray     |
| sync rd_gray       |                         | sync wr_gray       |
+--------------------+                         +--------------------+
       |                                              |
       +-- local full/overflow                        +-- local empty
```

跨域的核心不是同步每一根数据线，而是使用双时钟 FIFO：数据写入存储体，两个时钟域只同步对方的 Gray 编码指针。

## 3. 异步 FIFO 的关键机制

### 3.1 写时钟域

- 在 `adc_clk` 域用二进制写指针 `wr_bin` 寻址写 RAM。
- 每次接受 ADC 样本后，写指针加一。
- 将 `wr_bin` 转换为 Gray 指针 `wr_gray`。
- 用两级触发器把读域的 `rd_gray` 同步到 `adc_clk` 域。
- 根据“下一写指针”与同步后的读指针计算 `full`。
- `full`、ADC 域 `overflow` 和写入计数只能在 `adc_clk` 域产生。

### 3.2 读时钟域

- 在 `sys_clk` 域用二进制读指针 `rd_bin` 读取 RAM。
- 每次 packetizer 接受一个样本后，读指针加一。
- 将 `rd_bin` 转换为 Gray 指针 `rd_gray`。
- 用两级触发器把写域的 `wr_gray` 同步到 `sys_clk` 域。
- 根据当前读指针与同步后的写指针计算 `empty`。
- `empty`、读数据有效和 packetizer 侧的 backpressure 只在 `sys_clk` 域使用。

经典 Gray 指针异步 FIFO 通常使用 2 的幂次深度，并为指针增加一位回绕位。满判断会比较下一写指针与读指针的反相高位；空判断则比较读指针与同步后的写指针。

## 4. 复位和状态信号

- `adc_clk` 与 `sys_clk` 都需要自己的同步复位释放电路；异步复位可以作为触发器复位输入，但解除复位必须在各自时钟域同步完成。
- 两个指针在各自域复位为零，FIFO 只有在双方都完成复位后才允许正常传输。
- 不得把 ADC 域的 raw `full`、`overflow` 或计数器直接接到 `daq_ctrl`。
- 若系统域需要读取 ADC 域 overflow，应该同步一个事件、同步一个 Gray 计数器，或在 ADC 域保存计数后通过稳定快照/握手读取。
- `fifo_empty` 只能在 `sys_clk` 域驱动 packetizer；ADC 域的 `fifo_full` 只能在 `adc_clk` 域控制写入。

## 5. 对当前项目的改造边界

当前单时钟链路：

```text
sample_generator --(sys_clk)--> sync_fifo --(sys_clk)--> packetizer
```

未来接入真实 ADC 时建议改为：

```text
ADC --(adc_clk)--> async_fifo write --(sys_clk)--> async_fifo read --> packetizer
```

具体改动包括：

1. 用 ADC 接口和 `adc_clk` 域写侧替换 `sample_generator`；
2. 将当前 `sync_fifo` 替换为双时钟异步 FIFO，数据 RAM 使用 FPGA 的 dual-port BRAM 或厂商 FIFO IP；
3. 保持 packetizer、checksum 和 payload `ready` 在 `sys_clk` 域；
4. 将 ADC 域 overflow 通过 CDC 方案送入系统域统计；
5. 将 ADC 域复位、系统域复位和 FIFO 指针初始化分开设计，并定义上电后的允许传输时刻；
6. 对跨域控制命令使用 request/acknowledge 握手，而不是直接采样多位寄存器总线。

## 6. 不能采用的简化做法

- 不能用两级触发器同步 16-bit ADC 数据总线，然后把同步后的总线当作一个样本；两级同步只适合单比特控制信号。
- 不能只同步 `valid` 而不同步数据稳定窗口；`valid` 到达时数据可能已经改变。
- 不能把一个窄脉冲直接跨到更慢的时钟域；应改成 toggle、sticky flag 或 request/acknowledge 握手。
- 不能把两个时钟域的 `count` 直接相减；水位必须在指定域由同步后的 Gray 指针计算，或使用经过 CDC 的快照。
- 不能让两个时钟域同时驱动同一个普通寄存器或普通 RAM 端口。

## 7. 验证计划

异步 FIFO 真正实现后，至少需要验证：

- `adc_clk` 快于、慢于和接近 `sys_clk` 的情况；
- 两个时钟的相位持续变化，而不是固定相位关系；
- 随机写入、随机读出和随机 `ready` 背压；
- 满时写入被拒绝、空时读取被拒绝，且没有数据丢失或乱序；
- 复位发生在空闲、半满和持续传输期间；
- FIFO 水位边界、指针回绕和 Gray 指针同步延迟；
- CDC 静态检查、仿真断言以及 FPGA 厂商 FIFO/BRAM 推断报告。

本项目 Day 18 只完成设计说明，不新增异步 FIFO RTL；当前 `sync_fifo` 和 `daq_top` 仍保持单时钟实现。

## 8. 参考

- Clifford E. Cummings, *Simulation and Synthesis Techniques for Asynchronous FIFO Design*：<https://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf>
- 项目任务中给出的 CDC 参考：<https://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf>
