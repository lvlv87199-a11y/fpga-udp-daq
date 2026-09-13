# 每日项目记录

项目按每天约 2–3 小时、连续 30 天推进。下面记录每天的大致工作、结果和主要问题；“问题”也包含需要明确的设计决策。

| 天数 | 大致完成内容 | 主要问题或处理 |
|---|---|---|
| Day 1 | 建立项目目录；编写 README 和系统模块图；创建项目 skill；初始化本地 Git；创建并连接 GitHub 远程仓库。 | 环境没有 `gh` 命令，因此通过已登录的 GitHub 页面创建远程仓库；项目 `.git` 元数据受安全权限保护，绑定远程和提交时申请了项目范围内的 Git 权限。 |
| Day 2 | 检查并准备 WSL Ubuntu 22.04；确认 Python、Git；安装 Icarus Verilog、Verilator、GTKWave；验证版本命令。 | 初次查询 WSL 被 Windows 权限拦截，且输出存在编码问题；改用授权的 WSL 管理命令完成检查和安装。 |
| Day 3 | 学习 FIFO 的深度、满/空、读写握手和溢出处理；实现参数化单时钟同步 FIFO；完成 Icarus 编译和 Verilator lint。 | 规格没有预先规定复位和溢出语义，因此约定使用同步低有效复位、同步读出，并将满时被拒绝的写请求报告为一个时钟周期的 `overflow` 脉冲。首次编译时 Icarus 11 对 `parameter int unsigned` 声明报语法错误，改为 `parameter integer`；Verilator 的位宽警告则通过显式的指针末值和深度常量修正。 |
| Day 4 | 编写最小 SystemVerilog testbench；验证复位、空读、连续写入、满状态、溢出脉冲、顺序读取和复位恢复；生成并分析 VCD。 | 当前测试没有阻塞问题；波形查看依赖 WSLg 或可用的图形显示环境，VCD 文件本身已由仿真生成。 |

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

## 后续记录规则

后续每天完成任务后，在表格中追加一行，并在对应小节记录关键接口、验证结果和阻塞问题。
