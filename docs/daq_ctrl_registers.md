# DAQ 控制寄存器

`daq_ctrl` 使用一个简化的单周期寄存器接口，不依赖 AXI。`wr_en` 或 `rd_en` 为一个时钟周期的请求脉冲，`addr` 使用字节地址。

| 地址 | 名称 | 读/写 | 位域 | 说明 |
|---:|---|:---:|---|---|
| `0x00` | `CONTROL` | RW | bit 0 `enable` | 采样器使能；其他位保留。 |
| `0x04` | `SAMPLE_DIVIDER` | RW | bit 15:0 | 采样分频值，复位值为 0。 |
| `0x08` | `SAMPLES_PER_PACKET` | RW | bit 15:0 | 每包采样数，复位值为 256；写入 0 会被忽略。 |
| `0x0c` | `STATUS` | RO | bit 0 `enable` | 当前使能状态。 |
|  |  |  | bit 1 `fifo_full` | FIFO 满状态输入。 |
|  |  |  | bit 2 `fifo_overflow` | FIFO 溢出输入。 |
| `0x10` | `SAMPLE_COUNT` | RO | 31:0 | 成功写入 FIFO 的样本事件累计数。 |
| `0x14` | `FRAME_COUNT` | RO | 31:0 | checksum 握手完成后的 packet 事件累计数。 |
| `0x18` | `FIFO_OVERFLOW_COUNT` | RO | 31:0 | FIFO 满时被拒绝写入事件累计数。 |
| `0x1c` | `CHECKSUM_ERROR_COUNT` | RO | 31:0 | 外部 checksum 校验错误事件累计数。 |

## 接口约定

- 写请求：`wr_en=1` 时，在当前时钟上升沿写入 `wdata`。
- 读请求：`rd_en=1` 时，在当前时钟上升沿采样地址；随后 `rd_valid=1` 一个周期，`rdata` 给出读回值。
- 未映射地址读回 0，未映射地址写入无副作用。
- 复位为同步低有效复位 `rst_n`。
- 当前版本不提供写响应、读错误码或 AXI 通道；后续需要接入 SoC 时再包装为 AXI-Lite/CSR 接口。
- 四个统计寄存器在同步复位时清零，收到对应事件时每次加一，达到 `0xffffffff` 后自然回绕；当前不提供软件清零或饱和模式。
