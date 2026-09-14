# 每日项目记录

项目按每天约 2–3 小时、连续 30 天推进。下面记录每天的大致工作、结果和主要问题；“问题”也包含需要明确的设计决策。

| 天数 | 大致完成内容 | 主要问题或处理 |
|---|---|---|
| Day 1 | 建立项目目录；编写 README 和系统模块图；创建项目 skill；初始化本地 Git；创建并连接 GitHub 远程仓库。 | 环境没有 `gh` 命令，因此通过已登录的 GitHub 页面创建远程仓库；项目 `.git` 元数据受安全权限保护，绑定远程和提交时申请了项目范围内的 Git 权限。 |
| Day 2 | 检查并准备 WSL Ubuntu 22.04；确认 Python、Git；安装 Icarus Verilog、Verilator、GTKWave；验证版本命令。 | 初次查询 WSL 被 Windows 权限拦截，且输出存在编码问题；改用授权的 WSL 管理命令完成检查和安装。 |
| Day 3 | 学习 FIFO 的深度、满/空、读写握手和溢出处理；实现参数化单时钟同步 FIFO；完成 Icarus 编译和 Verilator lint。 | 规格没有预先规定复位和溢出语义，因此约定使用同步低有效复位、同步读出，并将满时被拒绝的写请求报告为一个时钟周期的 `overflow` 脉冲。首次编译时 Icarus 11 对 `parameter int unsigned` 声明报语法错误，改为 `parameter integer`；Verilator 的位宽警告则通过显式的指针末值和深度常量修正。 |
| Day 4 | 编写最小 SystemVerilog testbench；验证复位、空读、连续写入、满状态、溢出脉冲、顺序读取和复位恢复；生成并分析 VCD。 | 当前测试没有阻塞问题；波形查看依赖 WSLg 或可用的图形显示环境，VCD 文件本身已由仿真生成。 |
| Day 5 | 学习 `valid/ready` 数据流握手；实现 16-bit 参数化递增采样器；支持 `enable` 和可配置分频；完成 Icarus 编译、Verilator lint 和 smoke test。 | 需要明确 `enable` 与握手的关系：当一个样本已经 `valid` 时，即使 `enable` 拉低，也必须保持该样本直到 `ready` 接收，避免违反 valid/ready 协议。 |
| Day 6 | 学习寄存器映射和 FPGA 外设控制；实现 `daq_ctrl` 自定义读写接口、控制寄存器和状态寄存器；完成 Icarus 编译、Verilator lint 和寄存器 smoke test。 | 为避免过早引入 AXI，先规定单周期 `wr_en/rd_en` 接口；同时明确读响应为注册输出 `rd_valid`，未映射地址读回 0，零包长写入被忽略。 |
| Day 7 | 复盘前 6 天内容；核对 FIFO、采样器和控制寄存器的接口；编写 `docs/spec_v1.md`，统一模块、时钟复位、采样格式、寄存器和异常策略。 | 将尚未实现的 packetizer、顶层集成、CDC 和真实硬件明确列为后续范围，避免 v1 规格与当前 RTL 能力混淆。 |
| Day 8 | 学习有限状态机和状态转移；实现固定长度 payload packetizer；处理 FIFO 同步读延迟、payload `valid/ready` 背压和 `payload_last`；完成 packetizer smoke test。 | FIFO 是同步读出，不能在发出读请求的同一时刻直接使用新数据，因此增加 `ST_READ_CAPTURE` 状态；payload 端未 ready 时保持数据和 last 不变。Verilator 首次同时检查两个 RTL 文件时报告 `MULTITOP`，改用 `--top-module packetizer` 后通过。 |
| Day 9 | 学习帧头、魔数、帧序号、长度字段和校验字段；定义 `DAQ1` 应用帧格式、16-byte header、16-bit 样本 payload 和 XOR16 checksum；完成 `docs/packet_format.md`。 | 需要在网络字节序、字段长度和校验范围之间做明确约定；v1 统一使用大端多字节字段，`payload_length` 以字节计，checksum 只覆盖采样 payload。 |
| Day 10 | 学习 checksum/CRC 的工程意义；在 packetizer 中增加 payload XOR16 累加和独立 checksum 握手；验证输入停止后仍能输出完整 payload 与 checksum。 | checksum 必须在最后一个 payload 被真正接收时计算，不能在 payload 被 backpressure 时重复累加；因此在末 beat 使用 `checksum_accum ^ payload_data` 锁存最终值，并等待 `checksum_ready` 后再报告 `packet_done`。 |
| Day 11 | 学习 cocotb 的协程、驱动器、监视器和断言；安装 cocotb 并为 `sync_fifo` 编写第一个 Python 测试。 | 系统 Python 最初没有 pip，需要先补齐 WSL 的 `python3-pip`；测试直接驱动 RTL 顶层端口，并用协程封装写入、读出和状态检查。`bash sim/run_fifo_cocotb.sh` 已通过。 |
| Day 12 | 学习随机测试和参考模型；用 Python `deque` 模拟 FIFO，逐周期随机驱动读写并比较 `dout/full/empty/overflow`。 | 需要按时钟沿之前的 FIFO 状态判断读写是否真正被接受；满时写入被拒绝但同周期读出仍可发生，空时读出被忽略但同周期写入仍可发生。最终测试包含 2,000 个确定性随机周期，记录到 103 次空读、174 次满写溢出、1,013 次有效读和 1,013 次有效写。 |
| Day 13 | 学习 scoreboard/reference model；实现 `scripts/reference_packet.py`，根据样本生成 DAQ v1 应用帧，并提供帧解析与校验自检。 | 用 `struct` 固定大端字段布局，明确样本值、样本数、序号和 flags 的范围；自检验证 `DAQ1` 帧头、样本字节序和 `0x1234 ^ 0xabcd = 0xb9f9`。 |
| Day 14 | 学习测试覆盖矩阵；为 packetizer 编写 cocotb 覆盖测试，验证包长、payload 顺序、`payload_last`、背压、checksum 和不完整尾包等待策略；新增 `docs/testplan.md`。 | 当前 packetizer 还没有帧头/`frame_seq` 端口，因此帧序号先由 Day 13 参考模型验证，并在测试计划中明确列为 RTL 后续接口项。 |
| Day 15 | 学习顶层集成与接口分层；实现 `rtl/daq_top.sv`，连接 `daq_ctrl`、`sample_generator`、`sync_fifo` 和 `packetizer`；通过寄存器配置真实数据链路。 | 顶层用 `!fifo_full` 生成采样器 ready，避免正常数据路径向满 FIFO 发起写入；新增 cocotb 集成测试，验证配置后连续输出 0–7 两个 4-sample packet。 |
| Day 16 | 学习事件计数器、计数器回绕和复位恢复；增加样本数、发送帧数、FIFO overflow 数和 checksum 错误数四个 32-bit 只读统计寄存器。 | `sample_event`、`frame_event` 和 `checksum_error_event` 作为事件输入，计数器同步复位并自然回绕；顶层把 FIFO 写入和 `packet_done` 接到对应统计事件，checksum 错误保留为外部输入。 |
| Day 17 | 学习 ready/valid backpressure；新增随机拉低 `payload_ready`/`checksum_ready` 的顶层测试，并记录 FIFO 最大水位。 | 采用固定随机种子验证 64 个连续样本和 8 个 packet；新增 `sync_fifo.level`/`daq_top.fifo_level` 只读观测信号，不改变 FIFO 读写语义。测试通过：最大水位 8、payload 背压 46 次、checksum 背压 3 次、FIFO overflow 0。 |
| Day 18 | 学习时钟域跨越风险和异步 FIFO 原理；编写 `docs/cdc_note.md`，说明 ADC 时钟与系统时钟不同时时钟域、指针、复位和状态信号的处理方式。 | 本日按计划不实现异步 FIFO；明确使用 Gray 指针、双触发器同步、双口 RAM 和各域本地 `full/empty`，并列出后续 CDC 验证项目。 |
| Day 19 | 学习采样带宽、帧率、协议开销和有效数据率；新增 `scripts/throughput_report.py`，比较 256、512、736 样本/帧。 | 默认按 1 MSPS、16 bit、每帧 42 字节 Ethernet+IPv4+UDP 开销计算；线速率分别为 17.875、16.938、16.652 Mbit/s，有效率分别为 89.510%、94.465%、96.084%；736 样本应用帧为 1490 字节，脚本提示其超过 1472-byte UDP/IPv4 payload 限制。 |
| Day 20 | 学习 UDP payload 与 Ethernet MTU 的关系；将 DAQ 每帧配置限制在典型 IPv4/UDP payload 上限内；更新吞吐率脚本并输出 MTU 对比表。 | 1500-byte MTU 减去 IPv4 20 字节和 UDP 8 字节后得到 1472-byte payload；DAQ 帧头和 checksum 共占 18 字节，因此 16-bit 样本安全上限为 727 个/帧。`daq_ctrl` 接受 727、拒绝 728 及以上；报告保留 736 作为越界对照。未新增统一 `daq_top` 波形，按本日文档要求暂不实现。 |

## Day 3 设计约定

- 文件：`rtl/sync_fifo.sv`
- `DATA_WIDTH` 和 `DEPTH` 均为参数，支持非 2 的幂次深度，读写指针到达末尾时显式回绕。
- `wr_en && !full` 才会真正写入；`rd_en && !empty` 才会真正读取。
- 满时的写请求不会覆盖旧数据，并在该周期输出 `overflow=1`。
- 空时的读请求被忽略；`dout` 保持上一次有效读取的数据。
- `dout` 在接受读请求的时钟沿更新，不采用 show-ahead（预读）语义。

## Day 4 波形讲解

波形文件为 `sim/sync_fifo_tb.vcd`。VCD 使用 `1 ps` 时间单位，因此 GTKWave 显示的 `0–136000 ps` 等于 `0–136 ns`。testbench 在下降沿改变输入，在下一个上升沿检查 FIFO，这样可以清楚地区分“请求”与“时序逻辑真正执行”的时刻。

建议在 GTKWave 中加入顶层 `sync_fifo_tb` 下的：

```text
clk, rst_n, wr_en, din, full, rd_en, dout, empty, overflow
```

再展开 `dut`，加入内部信号：

```text
count, rd_ptr, wr_ptr, do_read, do_write
```

### 1. 复位阶段：0–20 ns

- `rst_n=0`，FIFO 在上升沿同步复位。
- `count=0`、读写指针归零、`dout=0`。
- `empty=1`，`full=0`，`overflow=0`。

这说明复位后的 FIFO 没有有效数据，且不会误报溢出。

### 2. 空读阶段：约 20–30 ns

- `rd_en=1`，但 `empty=1`。
- 因此 `do_read=0`，不会读取存储器，`count` 保持为 0。
- `dout` 保持之前的值，`overflow` 不会因为空读而置位。

这里体现了读握手条件：`rd_en && !empty` 才是真正的读操作。

### 3. 连续写入阶段：约 30–65 ns

testbench 依次写入四个 8-bit 数据：

```text
0x11 -> 0x22 -> 0x33 -> 0x44
```

每次写入时：

- `wr_en=1` 且 `full=0`；
- `do_write=1`；
- `din` 在时钟上升沿被写入 FIFO；
- `count` 依次从 0 增加到 4。

第四个数据写入完成后，`full=1`，表示 FIFO 已满；`empty=0`。

### 4. 溢出阶段：约 70–85 ns

FIFO 已满时，testbench 继续尝试写入 `0xee`：

- `wr_en=1` 且 `full=1`；
- `do_write=0`，所以 `0xee` 不会覆盖已有数据；
- `overflow=1`，持续一个时钟周期；
- `count` 仍保持为 4。

这是本模块的溢出保护重点：满时拒绝写入，而不是破坏 FIFO 中原有的数据。

### 5. 顺序读取阶段：约 90–125 ns

读取操作按先进先出顺序得到：

```text
0x11 -> 0x22 -> 0x33 -> 0x44
```

在每个读时钟上升沿之后：

- `do_read=1`；
- `dout` 更新为下一个数据；
- `count` 减 1；
- `rd_ptr` 向下一个存储位置移动。

最后一个 `0x44` 被读出后，`count=0`、`empty=1`、`full=0`，证明数据顺序正确且没有丢失。

### 6. 复位恢复阶段：约 130–136 ns

再次拉低 `rst_n` 后，在下一个上升沿清空 FIFO。最终应回到：

```text
empty=1, full=0, overflow=0, count=0
```

### GTKWave 判断标准

查看波形时，重点确认以下关系：

```text
真正写入 = wr_en && !full
真正读取 = rd_en && !empty
满时写入 = do_write=0 且 overflow=1
读完全部数据 = dout 依次为 0x11、0x22、0x33、0x44，随后 empty=1
```

## Day 5 设计约定

- 文件：`rtl/sample_generator.sv`
- `sample_valid=1` 表示 `sample_data` 有效；只有 `sample_valid && sample_ready` 时才算一次成功传输。
- `sample_ready=0` 时，`sample_valid` 和 `sample_data` 保持不变，形成标准 backpressure 行为。
- 每次成功传输后，采样值递增 1，并等待 `sample_divider` 个空闲时钟周期再产生下一个样本。
- `sample_divider=0` 表示使用该寄存器接口允许的最短间隔。
- `enable=0` 时不产生新的样本；如果已有样本处于 `valid` 状态，仍保持到下游接收完成。
- 采样值只在复位时清零，达到数据位宽上限后自然回绕。

## 后续记录规则

后续每天完成任务后，在表格中追加一行，并在对应小节记录关键接口、验证结果和阻塞问题。
