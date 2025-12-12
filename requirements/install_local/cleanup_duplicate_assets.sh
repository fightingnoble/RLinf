#!/bin/bash
# ============================================================
# 清理重复的 assets 目录
# ============================================================
# 
# 此脚本用于清理旧版本下载脚本遗留的重复 assets 目录
# 新版本已统一使用 assets/ 子目录结构
#
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPOS_DIR="${WORKSPACE}/docker/torch-2.6/repos"

echo "========================================"
echo "清理重复的 assets 目录"
echo "========================================"
echo ""

# 检查旧位置的目录
OLD_MANISKILL="${REPOS_DIR}/.maniskill"
OLD_SAPIEN="${REPOS_DIR}/.sapien"
NEW_MANISKILL="${REPOS_DIR}/assets/.maniskill"
NEW_SAPIEN="${REPOS_DIR}/assets/.sapien"

# 检查新位置是否存在
if [ ! -d "$NEW_MANISKILL" ] || [ ! -d "$NEW_SAPIEN" ]; then
    echo "⚠ 警告：新位置的 assets 目录不存在！"
    echo "   请先运行 requirements/install_local/download.sh 下载 assets"
    exit 1
fi

# 检查旧位置是否存在
if [ ! -d "$OLD_MANISKILL" ] && [ ! -d "$OLD_SAPIEN" ]; then
    echo "✓ 没有发现重复的 assets 目录，无需清理"
    exit 0
fi

echo "发现重复的 assets 目录："
[ -d "$OLD_MANISKILL" ] && echo "  - $OLD_MANISKILL ($(du -sh "$OLD_MANISKILL" 2>/dev/null | cut -f1))"
[ -d "$OLD_SAPIEN" ] && echo "  - $OLD_SAPIEN ($(du -sh "$OLD_SAPIEN" 2>/dev/null | cut -f1))"
echo ""
echo "新的 assets 位于："
echo "  - $NEW_MANISKILL"
echo "  - $NEW_SAPIEN"
echo ""

read -p "确认删除旧目录？(y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    [ -d "$OLD_MANISKILL" ] && rm -rf "$OLD_MANISKILL" && echo "✓ 已删除 $OLD_MANISKILL"
    [ -d "$OLD_SAPIEN" ] && rm -rf "$OLD_SAPIEN" && echo "✓ 已删除 $OLD_SAPIEN"
    echo ""
    echo "✓ 清理完成，已释放空间"
else
    echo "取消删除"
fi

