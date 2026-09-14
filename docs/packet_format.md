# DAQ UDP 应用帧格式 v1

## 1. 目的与范围

本格式定义放在 UDP payload 中的 DAQ 应用数据帧。它不是 Ethernet、IP 或 UDP 头；网络协议头由后续 UDP 发送模块或软件栈负责。

v1 的目标是让软件端能够可靠地判断：

- 当前数据是否是本项目的 DAQ 帧；
- 帧是否丢失或乱序；
- 当前帧包含多少个样本；
- payload 是否被截断或破坏。

## 2. 总体布局

```text
+----------------------+----------------------+----------------+
| 16-byte frame header | sample payload       | 2-byte checksum|
| magic/version/seq    | sample_count x 16bit | XOR16          |
+----------------------+----------------------+----------------+
```

总帧长度：

```text
16 + payload_length + 2 bytes
```

所有多字节字段使用大端字节序（network byte order）。payload 中每个 16-bit 样本也按高字节在前、低字节在后的顺序发送。

## 3. 帧头字段

| 偏移 | 长度 | 字段 | 类型/值 | 说明 |
|---:|---:|---|---|---|
| 0 | 4 | `magic` | ASCII `DAQ1`，即 `44 41 51 31` | 帧同步和格式识别。 |
| 4 | 1 | `version` | `0x01` | 格式版本。 |
| 5 | 1 | `flags` | v1 必须为 `0x00` | 预留扩展位。 |
| 6 | 2 | `header_length` | `0x0010` | 帧头长度，单位为字节。 |
| 8 | 4 | `frame_seq` | 无符号 32-bit | 帧序号，第一帧从 0 开始，完成一帧后加 1。 |
| 12 | 2 | `sample_count` | 无符号 16-bit | 当前帧中的样本数。 |
| 14 | 2 | `payload_length` | 无符号 16-bit | 采样 payload 长度，单位为字节。 |

基本一致性约束：

```text
header_length   == 16
payload_length  == sample_count * 2
total_length    == header_length + payload_length + 2
```

`payload_length` 是字节数，不是样本数；这是解析器最容易混淆的字段。

## 4. 采样 payload

v1 固定每个样本为一个无符号 16-bit 值：

```text
sample[0] high_byte, sample[0] low_byte,
sample[1] high_byte, sample[1] low_byte,
...
```

例如，两个样本 `0x1234`、`0xabcd` 的 payload 为：

```text
12 34 AB CD
```

正常固定长度帧中，`sample_count` 等于配置的每包样本数。若后续支持尾包，`sample_count` 应填写尾包实际包含的样本数量。

## 5. 校验字段

校验字段位于 payload 之后，长度为 2 字节，大端存储一个 16-bit XOR 值：

```text
checksum = 16'h0000
for each 16-bit sample in payload:
    checksum = checksum ^ sample
```

v1 的 checksum 只覆盖采样 payload，不覆盖帧头和 checksum 字段本身。它是轻量级完整性检查，不等同于 CRC，也不能替代 UDP/IP 校验和。

对于 `0x1234` 和 `0xabcd`：

```text
0x1234 ^ 0xabcd = 0xb9f9
```

因此完整示例帧为：

```text
44 41 51 31  01 00 00 10  00 00 00 2A  00 02 00 04
12 34 AB CD  B9 F9
```

其中：

- `frame_seq = 42`；
- `sample_count = 2`；
- `payload_length = 4`；
- 总长度为 `16 + 4 + 2 = 22` 字节。

## 6. 默认帧参数

Day 8/Day 9 的默认 packetizer 配置为每帧 256 个 16-bit 样本：

```text
sample_count    = 256
payload_length  = 512 bytes
header_length   = 16 bytes
checksum        = 2 bytes
total_length    = 530 bytes
```

530 字节低于典型 UDP/IPv4 单包 1472 字节 payload 上限，后续仍需在性能分析阶段确认不同帧长的吞吐和开销。

## 7. 接收端解析顺序

软件解析器应按以下顺序检查：

1. 缓冲区至少包含 18 字节（最小帧：16-byte header + 2-byte checksum）。
2. 检查 `magic`、`version` 和 `header_length`。
3. 读取 `sample_count` 和 `payload_length`，检查 `payload_length == sample_count * 2`。
4. 检查实际缓冲区长度是否等于 `16 + payload_length + 2`。
5. 对 payload 计算 XOR16，并与末尾 checksum 比较。
6. 检查 `frame_seq` 与上一个有效帧的连续性；允许 32-bit 序号回绕。
7. 通过所有检查后，再将 payload 解码成 16-bit 样本序列。

## 8. 异常处理

| 异常 | 接收端行为 |
|---|---|
| magic/version/header_length 错误 | 丢弃当前帧并记录格式错误。 |
| 长度字段不一致 | 丢弃当前帧并记录长度错误。 |
| checksum 不一致 | 丢弃当前帧并记录校验错误。 |
| `frame_seq` 不连续 | 报告丢帧或乱序，但是否丢弃当前有效帧由上层策略决定。 |
| UDP 包丢失 | 通过序号缺口统计，不能由接收端自动恢复样本。 |

## 9. 与当前 RTL 的关系

Day 10 的 `packetizer.sv` 已在最后一个 payload beat 后输出 XOR16 checksum，并通过独立的 `checksum_valid/checksum_ready` 握手传输。帧头、序号和完整 UDP 发送路径仍属于后续工作。
