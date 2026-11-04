#!/usr/bin/env bash
# ==============================================================================
# Cognitally (formerly TokDash) One-Line Standalone Binary Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kamanager2012/tokdash-releases/main/install.sh | bash
# ==============================================================================
set -euo pipefail

REPO="kamanager2012/tokdash-releases"
BINARY_NAME="cognitally"
INSTALL_DIR="${HOME}/.local/bin"

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}==> 正在安装 Cognitally / TokDash 独立闭源发行版...${NC}"

# 1. 架构检测
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

if [ "$OS" != "linux" ]; then
    echo -e "${YELLOW}警告: 当前仅官方认证 Linux / Ubuntu 环境，其他系统仍在实验阶段。${NC}"
fi

# 2. 检查安装目录
mkdir -p "$INSTALL_DIR"

# 3. 获取最新版本并下载
LATEST_RELEASE_URL="https://github.com/${REPO}/releases/latest/download/${BINARY_NAME}"
TARGET_PATH="${INSTALL_DIR}/${BINARY_NAME}"
TEMP_PATH="${TARGET_PATH}.tmp"

echo -e "==> 正在从 GitHub Releases 下载预编译单文件可执行二进制..."
if command -v curl &>/dev/null; then
    curl -fsSL --progress-bar "$LATEST_RELEASE_URL" -o "$TEMP_PATH" || {
        # Fallback to local sibling dist if installing from repo clone
        if [ -f "$(dirname "$0")/cognitally" ]; then
            echo -e "${YELLOW}网络下载受阻，使用本地预置发布二进制...${NC}"
            cp "$(dirname "$0")/cognitally" "$TEMP_PATH"
        else
            echo -e "${RED}下载失败，请检查网络连接或 GitHub 访问情况。${NC}"
            exit 1
        fi
    }
elif command -v wget &>/dev/null; then
    wget -q --show-progress "$LATEST_RELEASE_URL" -O "$TEMP_PATH" || {
        echo -e "${RED}下载失败，请检查网络连接。${NC}"
        exit 1
    }
else
    echo -e "${RED}错误: 未找到 curl 或 wget，请先安装。${NC}"
    exit 1
fi

chmod 755 "$TEMP_PATH"
mv "$TEMP_PATH" "$TARGET_PATH"

# 4. 创建别名软链接
ln -sf "$TARGET_PATH" "${INSTALL_DIR}/tokdash"

# 5. PATH 检查
PATH_WARNING=""
case ":$PATH:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
        PATH_WARNING="true"
        ;;
esac

echo -e ""
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}🎉 Cognitally / TokDash 安装成功！${NC}"
echo -e "  • 独立二进制位置: ${BOLD}${TARGET_PATH}${NC}"
echo -e "  • 兼容别名:       ${BOLD}${INSTALL_DIR}/tokdash${NC}"
echo -e "${GREEN}${BOLD}================================================================${NC}"

if [ -n "$PATH_WARNING" ]; then
    echo -e "${YELLOW}提示: ${INSTALL_DIR} 尚未包含在您的 PATH 环境变量中。${NC}"
    echo -e "请在您的 ~/.bashrc 或 ~/.zshrc 末尾添加以下配置后重新载入："
    echo -e "  ${BOLD}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo -e ""
fi

# 6. 执行健康自检
echo -e "==> 正在运行本地 AI Coding Agent 探针自检..."
if [ -z "$PATH_WARNING" ]; then
    "$TARGET_PATH" --doctor || true
else
    "$TARGET_PATH" --doctor || true
fi

echo -e ""
echo -e "${BLUE}${BOLD}💡 常用快速启动指南：${NC}"
echo -e "  1. 终端毫秒级状态栏集成: ${BOLD}cognitally --install-statusline${NC}"
echo -e "  2. 启动只读 MCP 预算服务: ${BOLD}cognitally --mcp${NC}"
echo -e "  3. 诊断本机 Agent 日志:   ${BOLD}cognitally --doctor${NC}"
echo -e "  4. 预算超额状态快速核验: ${BOLD}cognitally --budget-check${NC}"
echo -e ""
