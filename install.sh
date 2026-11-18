#!/usr/bin/env bash
# ==============================================================================
# Cognitally (formerly TokDash) One-Line Standalone Binary Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kamanager2012/tokdash-releases/v0.1.1/install.sh | bash
# Options:
#   --no-doctor        Skip post-install agent probe check
#   --local            Prefer local repository binary if available
#   --version <tag>    Pin release tag (default: v0.1.1)
#   --uninstall        Remove installed cognitally / tokdash binaries
#   -h, --help         Show installer help
# ==============================================================================
set -euo pipefail

REPO="kamanager2012/tokdash-releases"
BINARY_NAME="cognitally"
RELEASE_TAG="${COGNITALLY_VERSION:-v0.1.1}"
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
        --version)
            if [ "$#" -lt 2 ]; then
                echo -e "${RED}错误: --version 需要指定版本号标签（例如 v0.1.1）${NC}" >&2
                exit 1
            fi
            RELEASE_TAG="$2"
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Cognitally (TokDash) Installer for Linux / macOS

Usage:
  bash install.sh [OPTIONS]

Options:
  --no-doctor        Skip running `cognitally --doctor` after installation
  --local            Install from local sibling `cognitally` binary instead of downloading
  --version <tag>    Pin GitHub release tag (default: v0.1.1)
  --uninstall        Remove cognitally and tokdash from INSTALL_DIR
  -h, --help         Show this help message

Environment Variables:
  COGNITALLY_INSTALL_DIR      Override target bin directory (default: $HOME/.local/bin)
  COGNITALLY_VERSION          Override release tag (default: v0.1.1)
  COGNITALLY_LOCAL_BINARY     Explicit path to a local cognitally binary
  COGNITALLY_EXPECTED_SHA256  Override expected SHA-256 digest (otherwise mandatory from SHA256SUMS)
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

echo -e "${BLUE}${BOLD}==> 正在安装 Cognitally / TokDash 独立发行版 (${RELEASE_TAG})...${NC}"

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

# 2. 准备安装目录与临时暂存区（失败时自动回滚清理，绝不覆写既有可运行版本）
mkdir -p "$INSTALL_DIR"
TEMP_PATH="${TARGET_PATH}.tmp.$$"
SUMS_TEMP="${TARGET_PATH}.sums.$$"
cleanup_tmp() {
    rm -f "$TEMP_PATH" "$SUMS_TEMP"
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

download_with_client() {
    local url="$1"
    local dest="$2"
    local quiet="${3:-false}"
    if command -v curl >/dev/null 2>&1; then
        if [ "$quiet" = true ]; then
            curl -fsSL "$url" -o "$dest"
        else
            curl -fsSL --progress-bar "$url" -o "$dest"
        fi
        return $?
    elif command -v wget >/dev/null 2>&1; then
        if [ "$quiet" = true ]; then
            wget -q "$url" -O "$dest"
        else
            wget -q --show-progress "$url" -O "$dest"
        fi
        return $?
    else
        return 127
    fi
}

# 3. 获取二进制并锁定对应来源的 SHA256SUMS
TAG_RELEASE_BASE="https://github.com/${REPO}/releases/download/${RELEASE_TAG}"
LATEST_RELEASE_BASE="https://github.com/${REPO}/releases/latest/download"
RAW_TAG_BASE="https://raw.githubusercontent.com/${REPO}/${RELEASE_TAG}"
USED_LOCAL=false
LOCAL_DIR=""
SOURCE_SUMS_URL=""

if [ -n "${COGNITALLY_LOCAL_BINARY:-}" ]; then
    if [ ! -f "$COGNITALLY_LOCAL_BINARY" ]; then
        echo -e "${RED}错误: COGNITALLY_LOCAL_BINARY 指向的文件不存在: ${COGNITALLY_LOCAL_BINARY}${NC}" >&2
        exit 1
    fi
    echo -e "==> 使用 COGNITALLY_LOCAL_BINARY 指定的本地二进制: ${COGNITALLY_LOCAL_BINARY}"
    cp "$COGNITALLY_LOCAL_BINARY" "$TEMP_PATH"
    USED_LOCAL=true
    LOCAL_DIR="$(cd "$(dirname "$COGNITALLY_LOCAL_BINARY")" && pwd)"
elif [ "$PREFER_LOCAL" = true ] && [ -n "$LOCAL_SIBLING" ]; then
    echo -e "==> 使用本地仓库二进制: ${LOCAL_SIBLING}"
    cp "$LOCAL_SIBLING" "$TEMP_PATH"
    USED_LOCAL=true
    LOCAL_DIR="$SCRIPT_DIR"
else
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        if [ -n "$LOCAL_SIBLING" ]; then
            echo -e "${YELLOW}未检测到 curl/wget，回退使用本地预置发布二进制...${NC}"
            cp "$LOCAL_SIBLING" "$TEMP_PATH"
            USED_LOCAL=true
            LOCAL_DIR="$SCRIPT_DIR"
        else
            echo -e "${RED}错误: 未找到 curl 或 wget，请先安装其中之一。${NC}" >&2
            exit 1
        fi
    else
        echo -e "==> 正在从 GitHub Releases (${RELEASE_TAG}) 下载独立可执行二进制..."
        if download_with_client "${TAG_RELEASE_BASE}/${BINARY_NAME}" "$TEMP_PATH"; then
            SOURCE_SUMS_URL="${TAG_RELEASE_BASE}/SHA256SUMS"
        elif download_with_client "${LATEST_RELEASE_BASE}/${BINARY_NAME}" "$TEMP_PATH"; then
            echo -e "${YELLOW}指定标签下载受阻，已切换 GitHub Releases latest。${NC}"
            SOURCE_SUMS_URL="${LATEST_RELEASE_BASE}/SHA256SUMS"
        elif download_with_client "${RAW_TAG_BASE}/${BINARY_NAME}" "$TEMP_PATH"; then
            echo -e "${YELLOW}Releases 下载受阻，已切换 ${RELEASE_TAG} 仓库镜像源。${NC}"
            SOURCE_SUMS_URL="${RAW_TAG_BASE}/SHA256SUMS"
        elif [ -n "$LOCAL_SIBLING" ]; then
            echo -e "${YELLOW}网络下载受阻，使用本地预置发布二进制...${NC}"
            cp "$LOCAL_SIBLING" "$TEMP_PATH"
            USED_LOCAL=true
            LOCAL_DIR="$SCRIPT_DIR"
        else
            echo -e "${RED}下载失败，请检查网络连接或 GitHub 访问情况（保留原有安装未改动）。${NC}" >&2
            exit 1
        fi
    fi
fi

# 4. 校验 Zipapp 归档结构 + 强制 SHA-256 完整性校验（Fail-Closed）
if ! python3 -c 'import sys, zipfile; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)' "$TEMP_PATH"; then
    echo -e "${RED}错误: 获取到的文件不是有效的 Python Zipapp 归档（已中止并保留旧版）。${NC}" >&2
    exit 1
fi

compute_sha256() {
    local target="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$target" | awk '{print tolower($1)}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$target" | awk '{print tolower($1)}'
    else
        python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest().lower())' "$target"
    fi
}

EXPECTED_SHA256="$(printf '%s' "${COGNITALLY_EXPECTED_SHA256:-}" | tr '[:upper:]' '[:lower:]')"
if [ -z "$EXPECTED_SHA256" ]; then
    if [ "$USED_LOCAL" = true ]; then
        LOCAL_SUMS=""
        if [ -n "$LOCAL_DIR" ] && [ -f "${LOCAL_DIR}/SHA256SUMS" ]; then
            LOCAL_SUMS="${LOCAL_DIR}/SHA256SUMS"
        elif [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/SHA256SUMS" ]; then
            LOCAL_SUMS="${SCRIPT_DIR}/SHA256SUMS"
        fi
        if [ -n "$LOCAL_SUMS" ]; then
            EXPECTED_SHA256="$(awk '$2 == "cognitally" {print tolower($1); exit}' "$LOCAL_SUMS" || true)"
        fi
    else
        echo -e "==> 正在获取并校验 SHA256SUMS..."
        if download_with_client "$SOURCE_SUMS_URL" "$SUMS_TEMP" true || download_with_client "${RAW_TAG_BASE}/SHA256SUMS" "$SUMS_TEMP" true; then
            EXPECTED_SHA256="$(awk '$2 == "cognitally" {print tolower($1); exit}' "$SUMS_TEMP" || true)"
        fi
    fi
fi

if ! printf '%s' "$EXPECTED_SHA256" | grep -Eq '^[0-9a-f]{64}$'; then
    echo -e "${RED}错误: 缺少有效的 SHA-256 预期摘要（未获取到 SHA256SUMS 或格式非法），已拒绝覆盖安装。${NC}" >&2
    exit 1
fi

ACTUAL_SHA256="$(compute_sha256 "$TEMP_PATH")"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo -e "${RED}错误: SHA-256 校验失败！期望 ${EXPECTED_SHA256}，实际 ${ACTUAL_SHA256}（已保留原有版本）。${NC}" >&2
    exit 1
fi
echo -e "  • SHA-256 校验通过: ${ACTUAL_SHA256}"

# 5. 校验全通过后再原子替换目标二进制与兼容别名
chmod 755 "$TEMP_PATH"
mv -f "$TEMP_PATH" "$TARGET_PATH"
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
echo -e "  1. 终端多维用量看板:     ${BOLD}cognitally${NC}"
echo -e "  2. 查看完整命令手册:     ${BOLD}cognitally --help${NC}"
echo -e "  3. 终端毫秒级状态栏集成: ${BOLD}cognitally --install-statusline${NC}"
echo -e "  4. 启动只读 MCP 预算服务: ${BOLD}cognitally --mcp${NC}"
echo -e "  5. 诊断本机 Agent 日志:   ${BOLD}cognitally --doctor${NC}"
echo -e "  6. 预算超额状态快速核验: ${BOLD}cognitally --budget-check${NC}"
echo -e ""
