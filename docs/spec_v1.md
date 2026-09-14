# FPGA UDP DAQ 规格说明 v1

## 1. 文档范围

本版本定义无硬件 FPGA 采集系统的基础 RTL 接口和控制约定。当前已实现并验证的模块为：

- `sample_generator`：产生递增采样数据，并提供 `valid/ready` 数据流接口。
- `sync_fifo`：单时钟同步 FIFO，负责暂存采样数据和报告满时写入失败。
- `daq_ctrl`：提供简单的控制/状态寄存器接口。

UDP packetizer、顶层集成、真实 ADC、以太网 PHY 和跨时钟域逻辑属于后续版本。

## 2. 系统模块图

```text
                         +----------------+
                         |    daq_ctrl    |
                         | enable/divider |
                         | packet length  |
                         +-------+--------+
                                 |
                                 v
+------------------+      +-----+------+      +------------------+
| sample_generator |      |  sync_fifo  |      |   packetizer     |
| 16-bit increment |----->| buffer/data |----->| future module    |
| valid/ready      |      | full/empty  |      | UDP frame output |
+------------------+      +-----+------+      +------------------+
                                  |
                                  +---- fifo_full/overflow ----> daq_ctrl
```

在当前版本中，采样器和 FIFO 仍可独立仿真，尚未由 `daq_top` 连接成完整系统。

## 3. 模块功能

### 3.1 `sample_generator`

- 默认产生 16-bit 无符号递增样本，从 0 开始，每次成功传输后加 1。
- `sample_valid=1` 表示 `sample_data` 有效。
- 只有 `sample_valid && sample_ready` 时才消耗一个样本。
- 当 `sample_ready=0` 时，`sample_valid` 和 `sample_data` 保持稳定。
- `enable=0` 时不产生新样本；若已有样本处于 `valid` 状态，仍保持到被接收。
- `sample_divider` 表示一次成功传输后等待的空闲时钟周期数。
- 样本计数达到数据位宽上限后自然回绕。

### 3.2 `sync_fifo`

- 默认数据宽度为 16 bit，默认深度为 16，可通过参数修改。
- `wr_en && !full` 时写入 `din`；`rd_en && !empty` 时读取并在时钟沿更新 `dout`。
- 指针显式回绕，因此支持非 2 的幂次深度。
- 读写使用同一个 `clk`，当前版本不是异步 FIFO。
- `overflow` 是满时尝试写入产生的单周期脉冲。

### 3.3 `daq_ctrl`

- 使用 `wr_en/rd_en + addr + wdata/rdata` 的自定义寄存器接口。
- 写请求在时钟上升沿更新控制输出。
- 读请求在采样地址的时钟沿之后产生一个周期的 `rd_valid`，同时 `rdata` 有效。
- 输出控制信号为 `enable`、`sample_divider` 和 `samples_per_packet`。
- 状态输入为 `fifo_full` 和 `fifo_overflow`，通过 `STATUS` 寄存器读出。

## 4. 时钟与复位

- 当前所有模块使用单一时钟 `clk`。
- 复位信号为同步低有效 `rst_n`。
- 只有在 `posedge clk` 且 `rst_n=0` 时，寄存器状态才被清零或恢复默认值。
- 复位默认值：
  - `sample_generator.sample_data=0`，`sample_valid=0`；
  - `sync_fifo.count=0`，`empty=1`，`full=0`，`overflow=0`；
  - `daq_ctrl.enable=0`，`sample_divider=0`，`samples_per_packet=256`。
- 当前不处理 ADC 时钟与系统时钟不同的情况；后续需要异步 FIFO 或 CDC 处理。

## 5. 采样格式

- 采样类型：无符号整数。
- 默认采样宽度：16 bit。
- 采样序列：`0, 1, 2, ...`，溢出后按 16-bit 自然回绕。
- FIFO 的 `din/dout` 默认也是 16 bit，并保持样本值不变。
- 当前版本尚未定义 UDP payload 的字节序；该内容在 packetizer 和帧格式规格中定义。

## 6. 寄存器表

寄存器接口为 32-bit 数据宽度，地址使用字节地址。详细说明见 [`daq_ctrl_registers.md`](daq_ctrl_registers.md)。

| 地址 | 名称 | 属性 | 位域 | 复位值 |
|---:|---|:---:|---|---:|
| `0x00` | `CONTROL` | RW | bit 0 `enable` | `0` |
| `0x04` | `SAMPLE_DIVIDER` | RW | bit 15:0 | `0` |
| `0x08` | `SAMPLES_PER_PACKET` | RW | bit 15:0 | `256` |
| `0x0c` | `STATUS` | RO | bit 0 `enable`；bit 1 `fifo_full`；bit 2 `fifo_overflow` | 动态 |

寄存器行为约定：

- 写入未映射地址无副作用。
- 读取未映射地址返回 0。
- 写入 `SAMPLES_PER_PACKET=0` 被忽略，保持原值。
- 当前接口不提供写响应、错误码或 AXI 通道。
- v1 不约定同一周期同时读写同一地址；软件应一次只发起一个请求。

## 7. 异常处理策略

| 场景 | 行为 |
|---|---|
| FIFO 满时写入 | 拒绝写入，不覆盖旧数据，`overflow` 输出一个周期脉冲。 |
| FIFO 空时读取 | 忽略读取，`dout` 保持上一次有效读取值。 |
| 下游 `ready=0` | 采样器保持 `valid` 和数据，直到握手完成。 |
| `enable` 拉低时已有 pending sample | 不撤回已经声明有效的样本，等待下游接收。 |
| 零包长配置 | `daq_ctrl` 忽略写入，保留原来的 `samples_per_packet`。 |
| 未映射寄存器访问 | 读回 0，写入无副作用。 |
| 复位 | 在时钟上升沿恢复各模块默认状态。 |
| 溢出状态读取 | 当前 `STATUS[2]` 直接反映 `fifo_overflow` 输入，不是 sticky 状态；后续统计寄存器再增加累计计数。 |

## 8. 当前验证结果

- `sync_fifo`：Icarus 仿真验证写入、读取、满、空、溢出和顺序保持。
- `sample_generator`：验证 valid/ready backpressure、分频、递增和 enable 行为。
- `daq_ctrl`：验证寄存器默认值、读写、状态组合和非法包长处理。
- Icarus Verilog 编译与 Verilator lint 均已通过。

## 9. 当前限制与后续工作

- 尚未实现 `daq_top` 顶层集成。
- 尚未实现 packetizer、UDP 帧格式和 checksum。
- 尚未加入跨时钟域异步 FIFO。
- 尚未进行 Vivado 综合、实现、时序和资源分析。
- 尚未连接真实 ADC、PHY 或开发板。
