<div align="center">

# 🧠 Cognitally (formerly TokDash)

**Sovereign AI Coding Agent Observability, Token Ledger & MCP Budget Guard for Linux / Ubuntu**

*Zero-latency passive stream accounting across 14 mainstream AI coding agents + Read-only Autonomous MCP Budget Defense.*

[![Version](https://img.shields.io/badge/Release-v0.1.0-brightgreen.svg)](https://github.com/kamanager2012/tokdash-releases/releases)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%2F%20Linux-orange.svg)](https://ubuntu.com/)
[![MCP 2024-11-05](https://img.shields.io/badge/MCP-2024--11--05-8A2BE2.svg)](https://modelcontextprotocol.io/)
[![Zero Proxy](https://img.shields.io/badge/Proxy-Zero%20Overhead-success.svg)](#)
[![License: Free for Personal Use](https://img.shields.io/badge/License-Free%20for%20Personal%20Use-blue.svg)](#)

[快速开始](#-快速安装一行流) • [MCP 智能体配置](#-mcp-智能体即插即用) • [终端状态栏](#-毫秒级终端状态栏) • [支持的 14 款 Agent](#-支持的-14-款-ai-coding-agent)

</div>

---

## 💡 为什么选择 Cognitally / TokDash？

当开发者高频使用 **Claude Code、Codex、Cursor、Qoder** 等自主编程智能体时，普遍面临三大痛点：
1. **“Token 刺客”**：睡觉前让 Agent 自动跑重构测试，早上一看死循环刷爆卡里几十刀；
2. **“多 Agent 碎片化”**：机器上装了 4、5 款 Agent，各个平台账单割裂，无法核算每日总体研发成本；
3. **“传统代理损耗”**：云端监控或中间人代理（Proxy）会劫持网络、增加请求延迟、甚至有泄露私有提示词的风险。

**Cognitally 的核心解法：**
- **零网络代理、零延迟损耗**：采用纯标准库 `flock` 原子快照，在底层被动单飞解析本地日志与 SQLite 会话，CPU 占用趋近于 0，不经过任何外部转发。
- **14 款 Agent 财务级统一账本**：全口径覆盖国内外主流工具，精准识别 Cache Read / Cache Write / Input / Output / Reasoning 真实 Token 消耗与来源矩阵。
- **主动式 MCP 预算守卫 (`check_budget`)**：业界首个通过标准 Model Context Protocol 让 AI Coding Agent 在执行重型推理前自查预算水位的天文台服务。

---

## ⚡ 快速安装（一行流）

在 Linux / Ubuntu 终端中直接运行官方独立二进制一键安装脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/kamanager2012/tokdash-releases/main/install.sh | bash
```

安装完成后，全局自动获得 `cognitally` 及兼容别名 `tokdash` 命令：

```bash
# 诊断本机主流 Agent 安装与日志健康度
cognitally --doctor

# 极速输出当前 Token 消耗与预算状态
cognitally --statusline
```

---

## 🔌 MCP 智能体即插即用

Cognitally 原生内置标准 Stdio MCP 2024-11-05 协议服务。通过以下配置，即可让您的编程智能体拥有“开销自省”与“预算防线”能力：

### 1. Claude Code
```bash
claude mcp add cognitally -- cognitally --mcp
```

### 2. Cursor
在 `~/.cursor/mcp.json` 中添加：
```json
{
  "mcpServers": {
    "tokdash": {
      "command": "cognitally",
      "args": ["--mcp"]
    }
  }
}
```

### 3. Windsurf / Zed
在 `mcp_config.json` 中添加：
```json
{
  "mcpServers": {
    "cognitally": {
      "command": "cognitally",
      "args": ["--mcp"]
    }
  }
}
```

#### 智能体可用工具清单（严格只读）：
- `check_budget`：智能体自主评估今日/当周/当月消耗是否越界，返回剩余可用额度；
- `get_usage`：查询输入、输出、缓存读写与思维链 Token 明细；
- `get_cost`：查询各 Agent 与每日花费趋势；
- `get_quota`：读取 Codex、Claude、Cursor 等实时额度窗口与重置倒计时；
- `get_projects`：按工作区/代码仓归集用量与花费；
- `get_models`：按具体 LLM 模型分析开销；
- `get_accounting_status`：获取当前天文台日志解析探针健康状态。

---

## 💻 毫秒级终端状态栏 (Statusline)

将当天 AI 编程消耗与额度预警随手挂载到日常终端中：

```bash
# 查看适用于当前终端的装配指引
cognitally --install-statusline
```

### 效果预览：
```text
⚡ $12.40 | 3.2M tok | 4 agents
```
- **单行零换行**：安全嵌入 Bash PS1、Zsh PROMPT、Tmux 状态行与 Starship 自定义模块；
- **毫秒级返回**：复用原子快照缓存，无感知极速输出。

---

## 🤖 支持的 14 款 AI Coding Agent

| AI Coding Agent | 支持特性与采集方式 | 健康自检标识 |
| :--- | :--- | :---: |
| **Claude Code** | 会话转录流解析、提示词缓存读写拆解、Quota 额度 | `✅ OK` |
| **OpenAI Codex CLI** | Sessions JSONL 增量流解析、Token 对账 | `✅ OK` |
| **Cursor Composer** | CLI 转录流、Chats 会话与 Workspace 追踪 | `✅ OK` |
| **Google Antigravity / Gemini** | Protobuf 解码聚合、配额倒计时 | `✅ OK` |
| **Grok Build & Bot** | Sessions 结构解析、使用率账单对齐 | `✅ OK` |
| **GLM Code (ZCode)** | SQLite 本地账本被动核算 | `✅ OK` |
| **Qoder (IDE & CLI)** | 专有数据库与加密缓存解密对账 | `✅ OK` |
| **CodeBuddy / WorkBuddy** | 腾讯系编码助手日志增量扫描 | `✅ OK` |
| **Kimi Code** | 日志 JSONL 流解析与模型映射 | `✅ OK` |
| **DeepSeek Harness** | 会话解压流核算 | `✅ OK` |
| **OpenCode** | 本地数据目录与 SQLite 状态账本 | `✅ OK` |
| **Hermes Agent** | 本地状态数据库跟踪 | `✅ OK` |
| **Pi Agent CLI** | 会话与上下文追踪 | `✅ OK` |

---

## 🛡️ 安全与隐私声明 (Local-First Guarantee)

- **完全本地化**：所有会话分析均在您的本地机器完成，绝不向任何第三方服务器上传您的代码、Prompt 或敏感上下文；
- **只读零侵入**：以只读方式被动访问本地既有日志文件，不篡改 Agent 原始配置，不建立网络中间人拦截。

---

## 📦 发布说明与技术支持

- **最新版本**：`v0.1.0` (Linux x86_64 Standalone Executable)
- **问题反馈与建议**：欢迎在 [GitHub Issues](https://github.com/kamanager2012/tokdash-releases/issues) 提交反馈与功能提案。
