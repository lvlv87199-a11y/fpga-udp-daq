# FPGA UDP DAQ 规格说明 v1

## 1. 文档范围

本版本定义无硬件 FPGA 采集系统的基础 RTL 接口和控制约定。当前已实现并验证的模块为：

- `sample_generator`：产生递增采样数据，并提供 `valid/ready` 数据流接口。
- `sync_fifo`：单时钟同步 FIFO，负责暂存采样数据和报告满时写入失败。
- `daq_ctrl`：提供简单的控制/状态寄存器接口。
- `packetizer`：将 FIFO 样本组成固定长度 payload，并输出 XOR16 checksum。
- `daq_top`：在单一时钟域中连接上述模块，向外提供控制寄存器和 payload/checksum 流接口。

完整 UDP 传输头、真实 ADC、以太网 PHY 和跨时钟域逻辑属于后续版本。

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
| 16-bit increment |----->| buffer/data |----->| payload/checksum |
| valid/ready      |      | full/empty  |      | stream output    |
+------------------+      +-----+------+      +------------------+
                                  |
                                  +---- fifo_full/overflow ----> daq_ctrl
```

当前版本已由 `daq_top` 在单一时钟域中连接采样器、FIFO、控制寄存器和 packetizer；UDP 传输头和真实硬件仍不在范围内。

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
- 统计寄存器记录成功写入 FIFO 的样本数、完成帧数、FIFO 溢出数和外部 checksum 错误数。

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
| `0x10` | `SAMPLE_COUNT` | RO | bit 31:0 | `0` |
| `0x14` | `FRAME_COUNT` | RO | bit 31:0 | `0` |
| `0x18` | `FIFO_OVERFLOW_COUNT` | RO | bit 31:0 | `0` |
| `0x1c` | `CHECKSUM_ERROR_COUNT` | RO | bit 31:0 | `0` |

寄存器行为约定：

- 写入未映射地址无副作用。
- 读取未映射地址返回 0。
- 写入 `SAMPLES_PER_PACKET=0` 被忽略，保持原值。
- 当前接口不提供写响应、错误码或 AXI 通道。
- v1 不约定同一周期同时读写同一地址；软件应一次只发起一个请求。
- 四个统计计数器在同步复位时清零，事件到来时加一，32-bit 溢出后自然回绕。

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
| 溢出状态读取 | 当前 `STATUS[2]` 直接反映 `fifo_overflow` 输入，不是 sticky 状态；累计值通过 `FIFO_OVERFLOW_COUNT` 读取。 |

统计事件约定：

| 计数器 | 事件来源 |
|---|---|
| `SAMPLE_COUNT` | `sample_generator` 成功向 FIFO 交付一个样本。 |
| `FRAME_COUNT` | packetizer 的 `packet_done` 事件。 |
| `FIFO_OVERFLOW_COUNT` | FIFO 的 `overflow` 脉冲。 |
| `CHECKSUM_ERROR_COUNT` | 顶层 `checksum_error_event` 输入，由后续接收/校验模块上报。 |

## 8. 当前验证结果

- `sync_fifo`：Icarus 仿真验证写入、读取、满、空、溢出和顺序保持。
- `sample_generator`：验证 valid/ready backpressure、分频、递增和 enable 行为。
- `daq_ctrl`：验证寄存器默认值、读写、状态组合、非法包长处理和四类统计计数器。
- `daq_top`：验证寄存器配置后产生样本 0–7、完成两个 packet，并读回统计值 `samples=16`、`frames=2`、`fifo_overflows=0`、`checksum_errors=1`。
- Icarus Verilog 编译与 Verilator lint 均已通过。

## 9. 当前限制与后续工作

- `daq_top` 已完成单时钟顶层集成和 Day 16 统计计数器；UDP 发送模块仍未实现。
- packetizer 当前输出 payload/checksum 流，完整 UDP 应用帧头和 `frame_seq` 仍由后续模块负责。
- 尚未加入跨时钟域异步 FIFO。
- 尚未进行 Vivado 综合、实现、时序和资源分析。
- 尚未连接真实 ADC、PHY 或开发板。
