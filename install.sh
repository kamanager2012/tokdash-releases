#!/usr/bin/env bash
# ==============================================================================
# Cognitally (formerly TokDash) One-Line Standalone Binary Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kamanager2012/tokdash-releases/main/install.sh | bash
# Options:
#   --no-doctor    Skip post-install agent probe check
#   --local        Prefer local repository binary if available
#   --uninstall    Remove installed cognitally / tokdash binaries
#   -h, --help     Show installer help
# ==============================================================================
set -euo pipefail

REPO="kamanager2012/tokdash-releases"
BINARY_NAME="cognitally"
INSTALL_DIR="${COGNITALLY_INSTALL_DIR:-${HOME}/.local/bin}"

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

UNINSTALL=false
SKIP_DOCTOR=false
PREFER_LOCAL=false

if [ "${COGNITALLY_SKIP_DOCTOR:-0}" = "1" ]; then
    SKIP_DOCTOR=true
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        --uninstall)
            UNINSTALL=true
            ;;
        --no-doctor|--skip-doctor)
            SKIP_DOCTOR=true
            ;;
        --local)
            PREFER_LOCAL=true
            ;;
        -h|--help)
            cat <<'EOF'
Cognitally (TokDash) Installer for Linux / macOS

Usage:
  bash install.sh [OPTIONS]

Options:
  --no-doctor    Skip running `cognitally --doctor` after installation
  --local        Install from local sibling `cognitally` binary instead of downloading
  --uninstall    Remove cognitally and tokdash from INSTALL_DIR
  -h, --help     Show this help message

Environment Variables:
  COGNITALLY_INSTALL_DIR      Override target bin directory (default: $HOME/.local/bin)
  COGNITALLY_LOCAL_BINARY     Explicit path to a local cognitally binary
  COGNITALLY_EXPECTED_SHA256  Verify downloaded binary against expected SHA-256 digest
  COGNITALLY_SKIP_DOCTOR=1    Equivalent to --no-doctor
EOF
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1 (使用 --help 查看帮助)${NC}" >&2
            exit 1
            ;;
    esac
    shift
done

TARGET_PATH="${INSTALL_DIR}/${BINARY_NAME}"
ALIAS_PATH="${INSTALL_DIR}/tokdash"

if [ "$UNINSTALL" = true ]; then
    echo -e "${BLUE}${BOLD}==> 正在卸载 Cognitally / TokDash...${NC}"
    removed=0
    for item in "$TARGET_PATH" "$ALIAS_PATH"; do
        if [ -e "$item" ] || [ -L "$item" ]; then
            rm -f "$item"
            echo -e "  • 已移除: $item"
            removed=$((removed + 1))
        fi
    done
    if [ "$removed" -eq 0 ]; then
        echo -e "${YELLOW}未在 ${INSTALL_DIR} 发现已安装的 cognitally 或 tokdash。${NC}"
    else
        echo -e "${GREEN}${BOLD}✅ 卸载完成。${NC}"
    fi
    exit 0
fi

echo -e "${BLUE}${BOLD}==> 正在安装 Cognitally / TokDash 独立发行版...${NC}"

# 1. 系统与 Python 3 (>= 3.8) 运行时检查
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
    linux|darwin)
        ;;
    *)
        echo -e "${YELLOW}警告: 当前系统 ($OS) 非标准 Linux/macOS 环境，建议检查兼容模式。${NC}"
        ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RED}错误: 未找到 python3。Cognitally 需要 Python 3.8 或更高版本运行时。${NC}" >&2
    exit 1
fi

if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
    PY_VER="$(python3 --version 2>&1 || echo unknown)"
    echo -e "${RED}错误: 检测到 ${PY_VER}，需要 Python >= 3.8。${NC}" >&2
    exit 1
fi

# 2. 准备安装目录与临时文件
mkdir -p "$INSTALL_DIR"
TEMP_PATH="${TARGET_PATH}.tmp.$$"
cleanup_tmp() {
    rm -f "$TEMP_PATH"
}
trap cleanup_tmp EXIT

# 解析脚本所在目录（支持 pipe 执行与本地执行）
SCRIPT_SRC="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SRC" ] && [ -e "$SCRIPT_SRC" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SRC")" && pwd)"
else
    SCRIPT_DIR=""
fi
LOCAL_SIBLING=""
if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/${BINARY_NAME}" ]; then
    LOCAL_SIBLING="${SCRIPT_DIR}/${BINARY_NAME}"
fi

# 3. 多级获取二进制（显式本地 / Releases 最新版 / Raw main / 本地回退）
LATEST_RELEASE_URL="https://github.com/${REPO}/releases/latest/download/${BINARY_NAME}"
RAW_MAIN_URL="https://raw.githubusercontent.com/${REPO}/main/${BINARY_NAME}"
USED_LOCAL=false

download_with_client() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --progress-bar "$url" -o "$dest"
        return $?
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$url" -O "$dest"
        return $?
    else
        return 127
    fi
}

if [ -n "${COGNITALLY_LOCAL_BINARY:-}" ]; then
    if [ ! -f "$COGNITALLY_LOCAL_BINARY" ]; then
        echo -e "${RED}错误: COGNITALLY_LOCAL_BINARY 指向的文件不存在: ${COGNITALLY_LOCAL_BINARY}${NC}" >&2
        exit 1
    fi
    echo -e "==> 使用 COGNITALLY_LOCAL_BINARY 指定的本地二进制: ${COGNITALLY_LOCAL_BINARY}"
    cp "$COGNITALLY_LOCAL_BINARY" "$TEMP_PATH"
    USED_LOCAL=true
elif [ "$PREFER_LOCAL" = true ] && [ -n "$LOCAL_SIBLING" ]; then
    echo -e "==> 使用本地仓库二进制: ${LOCAL_SIBLING}"
    cp "$LOCAL_SIBLING" "$TEMP_PATH"
    USED_LOCAL=true
else
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        if [ -n "$LOCAL_SIBLING" ]; then
            echo -e "${YELLOW}未检测到 curl/wget，回退使用本地预置发布二进制...${NC}"
            cp "$LOCAL_SIBLING" "$TEMP_PATH"
            USED_LOCAL=true
        else
            echo -e "${RED}错误: 未找到 curl 或 wget，请先安装其中之一。${NC}" >&2
            exit 1
        fi
    else
        echo -e "==> 正在从 GitHub Releases 下载独立可执行二进制..."
        if download_with_client "$LATEST_RELEASE_URL" "$TEMP_PATH"; then
            :
        elif download_with_client "$RAW_MAIN_URL" "$TEMP_PATH"; then
            echo -e "${YELLOW}Releases 下载受阻，已自动切换 main 分支产物源。${NC}"
        elif [ -n "$LOCAL_SIBLING" ]; then
            echo -e "${YELLOW}网络下载受阻，使用本地预置发布二进制...${NC}"
            cp "$LOCAL_SIBLING" "$TEMP_PATH"
            USED_LOCAL=true
        else
            echo -e "${RED}下载失败，请检查网络连接或 GitHub 访问情况。${NC}" >&2
            exit 1
        fi
    fi
fi

# 4. 校验 zipapp 归档完整性与可选 SHA-256 摘要
if ! python3 -c 'import sys, zipfile; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)' "$TEMP_PATH"; then
    echo -e "${RED}错误: 获取到的文件不是有效的 Python Zipapp 归档（可能下载被拦截或已损坏）。${NC}" >&2
    exit 1
fi

compute_sha256() {
    local target="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$target" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$target" | awk '{print $1}'
    else
        python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$target"
    fi
}

EXPECTED_SHA256="${COGNITALLY_EXPECTED_SHA256:-}"
if [ -z "$EXPECTED_SHA256" ] && [ "$USED_LOCAL" = true ] && [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/SHA256SUMS" ]; then
    EXPECTED_SHA256="$(awk '$2 == "cognitally" {print $1; exit}' "${SCRIPT_DIR}/SHA256SUMS" || true)"
fi

if [ -n "$EXPECTED_SHA256" ]; then
    ACTUAL_SHA256="$(compute_sha256 "$TEMP_PATH")"
    if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        echo -e "${RED}错误: SHA-256 校验失败！期望 ${EXPECTED_SHA256}，实际 ${ACTUAL_SHA256}${NC}" >&2
        exit 1
    fi
    echo -e "  • SHA-256 校验通过: ${ACTUAL_SHA256}"
fi

chmod 755 "$TEMP_PATH"
mv "$TEMP_PATH" "$TARGET_PATH"

# 5. 创建兼容别名软链接
ln -sf "$TARGET_PATH" "$ALIAS_PATH"

# 6. PATH 检查
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
echo -e "  • 兼容别名:       ${BOLD}${ALIAS_PATH}${NC}"
echo -e "${GREEN}${BOLD}================================================================${NC}"

if [ -n "$PATH_WARNING" ]; then
    echo -e "${YELLOW}提示: ${INSTALL_DIR} 尚未包含在您的 PATH 环境变量中。${NC}"
    echo -e "请在您的 ~/.bashrc 或 ~/.zshrc 末尾添加以下配置后重新载入："
    echo -e "  ${BOLD}export PATH=\"${INSTALL_DIR}:\$PATH\"${NC}"
    echo -e ""
fi

# 7. 执行健康自检
if [ "$SKIP_DOCTOR" = false ]; then
    echo -e "==> 正在运行本地 AI Coding Agent 探针自检..."
    "$TARGET_PATH" --doctor || true
fi

echo -e ""
echo -e "${BLUE}${BOLD}💡 常用快速启动指南：${NC}"
echo -e "  1. 查看完整命令手册:     ${BOLD}cognitally --help${NC}"
echo -e "  2. 终端毫秒级状态栏集成: ${BOLD}cognitally --install-statusline${NC}"
echo -e "  3. 启动只读 MCP 预算服务: ${BOLD}cognitally --mcp${NC}"
echo -e "  4. 诊断本机 Agent 日志:   ${BOLD}cognitally --doctor${NC}"
echo -e "  5. 预算超额状态快速核验: ${BOLD}cognitally --budget-check${NC}"
echo -e ""
