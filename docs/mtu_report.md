# Day 20 MTU 与有效带宽分析

## 1. 约束

本项目按典型 Ethernet MTU 1500 bytes、IPv4 header 20 bytes 和 UDP header
8 bytes 计算：

```text
UDP payload limit = 1500 - 20 - 8 = 1472 bytes
```

DAQ 应用帧放在 UDP payload 中，还需要 16-byte 应用帧头和 2-byte XOR16
checksum。对于 16-bit 样本：

```text
max samples/frame = floor((1472 - 16 - 2) / 2) = 727
```

因此 `SAMPLES_PER_PACKET` 的安全范围是 1–727。RTL 控制寄存器会拒绝 0 和
大于 727 的配置。736 样本/帧保留在表中，用于展示超过 UDP payload 上限的结果。

## 2. 对比表

以下结果由 `python3 scripts/throughput_report.py` 生成，假设采样率为 1 MSPS、
样本宽度为 16 bit。线速率还包含每帧 42 bytes 的 Ethernet II + IPv4 + UDP
协议开销；不计 Ethernet FCS、前导码和帧间隙。

| 样本/帧 | 样本 payload | 应用帧长度 | 应用开销 | 线速帧长度 | 有效带宽 | 线速率 | 有效率 | UDP payload |
|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| 256 | 512 | 530 | 18 | 572 | 16.000 Mbit/s | 17.875 Mbit/s | 89.510% | 通过 |
| 512 | 1024 | 1042 | 18 | 1084 | 16.000 Mbit/s | 16.938 Mbit/s | 94.465% | 通过 |
| 727 | 1454 | 1472 | 18 | 1514 | 16.000 Mbit/s | 16.660 Mbit/s | 96.037% | 通过 |
| 736 | 1472 | 1490 | 18 | 1532 | 16.000 Mbit/s | 16.652 Mbit/s | 96.084% | 超限 |

其中“有效带宽”是原始采样数据率；“线速率”是包含应用帧头、checksum 和
网络协议头后的理论发送带宽；“有效率”定义为有效采样带宽/线速率。

## 3. 结论

- 默认 256 samples/frame 安全，但帧率和协议开销相对较高。
- 512 samples/frame 在安全范围内，开销明显下降，适合作为常用配置。
- 727 samples/frame 正好达到 1472-byte UDP payload 上限，是当前 16-bit
  DAQ 帧格式的最大安全配置。
- 736 samples/frame 的样本 payload 虽然正好是 1472 bytes，但加上应用帧头和
  checksum 后达到 1490 bytes，因此不能作为单个 IPv4/UDP payload 发送。

## 4. 可复现命令

```bash
python3 scripts/throughput_report.py --self-test
python3 scripts/throughput_report.py
```
