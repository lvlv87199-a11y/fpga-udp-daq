# FPGA UDP DAQ 测试计划 v1

## 1. 范围

本测试计划覆盖当前无硬件仿真阶段的 FIFO、packetizer 和 DAQ 应用帧参考模型。测试重点是数据顺序、固定包长、握手背压、checksum 和不完整尾包的处理。

当前 `rtl/packetizer.sv` 输出的是 payload 流和独立 checksum，尚未输出 16-byte UDP 应用帧头或 `frame_seq` 端口。因此帧序号目前由 Python 参考模型验证；packetizer RTL 的帧序号测试列为后续接口集成项，不伪造为已通过。

## 2. 运行命令

在 WSL Ubuntu 中执行：

```bash
bash sim/run_packetizer_cocotb.sh
python3 scripts/reference_packet.py --self-test
```

现有基础 SystemVerilog 测试仍可用：

```bash
bash sim/run_packetizer_tb.sh
```

## 3. 覆盖矩阵

| 编号 | 测试项 | 测试场景 | 预期结果 | 状态 |
|---|---|---|---|---|
| P01 | 包长 | 1、4、8 个样本/包 | 每包输出准确数量的 payload beat | PASS |
| P02 | payload 顺序 | 递增样本和非零起始值 | 输出顺序与 FIFO 输入一致 | PASS |
| P03 | `payload_last` | 每种包长的最后一个 beat | 只有最后一个 payload beat 为 1 | PASS |
| P04 | payload 背压 | 周期性拉低 `payload_ready` | `payload_valid/data/last` 保持稳定 | PASS |
| P05 | checksum | 1、4、8 个样本 | XOR16 等于所有已接受样本的异或 | PASS |
| P06 | checksum 背压 | `checksum_ready=0` 保持两个周期 | checksum 数据保持，ready 后完成握手 | PASS |
| P07 | 尾包策略 | 4 个样本包先只提供 2 个样本 | 不输出 checksum/`packet_done`，等待剩余样本 | PASS |
| P08 | 帧序号 | 参考模型生成 `frame_seq=0/1` | 大端序号字段正确 | PASS（参考模型） |
| P09 | packetizer RTL 帧序号 | 当前 packetizer 无帧头/序号端口 | 待后续帧头接口集成 | BLOCKED（接口未实现） |
| T01 | daq_top 控制链路 | 通过寄存器配置分频和包长，采集 0–7 并输出两包 | 控制、采样器、FIFO、packetizer 端到端顺序正确 | PASS |
| T02 | 统计寄存器 | 注入样本、帧、FIFO overflow、checksum error 事件 | 四个 32-bit 计数器分别加一并可读回 | PASS |

## 4. 尾包策略

当前策略是固定长度包：如果 packetizer 已经开始一个包但 FIFO 暂时没有足够样本，则停留在读请求状态等待数据。已经成功发送的 payload beat 保持有效协议，但在达到配置长度前不会输出 checksum，也不会产生 `packet_done`。

## 5. 验收标准

- P01–P07 的 cocotb 测试全部通过；
- 参考模型能够验证帧头、样本大端序和 XOR16 checksum；
- P09 在 packetizer 增加帧头/序号接口后补测；
- T01 验证 `daq_ctrl -> sample_generator -> sync_fifo -> packetizer` 的单时钟连接；
- T02 验证 Day 16 的四类事件计数器及同步复位默认值；
- 测试失败时，断言应指出数据、last、checksum 或状态不匹配位置。
