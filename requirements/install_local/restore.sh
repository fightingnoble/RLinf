#!/bin/bash
# ============================================================
# Git 仓库还原脚本
# ============================================================
# 
# 用途：将 docker/torch-2.6/repos/ 下所有 Git 仓库还原到干净状态
# 
# 操作：
#   1. git reset --hard HEAD  - 丢弃所有未提交的修改
#   2. git clean -fd          - 删除未跟踪的文件和目录
#   3. 删除所有 .backup 文件
# 
# ⚠️  警告：此操作不可逆！所有未提交的修改将被永久删除！
# 
# ============================================================

set -e

docker run --rm -v "$(pwd):/data" ubuntu:latest chown -R $(id -u):$(id -g) /data
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 修正 REPOS_DIR 路径，指向 docker/torch-2.6/repos
# SCRIPT_DIR 现在是 requirements/install_local/, 需要向上两级到项目根目录
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPOS_DIR="${PROJECT_ROOT}/docker/torch-2.6/repos"

# 颜色定义
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo "============================================================"
echo -e "${CYAN}  Git 仓库还原脚本${NC}"
echo "============================================================"
echo ""
echo -e "${YELLOW}⚠️  警告：此操作将执行以下操作：${NC}"
echo ""
echo "  1. 对所有 Git 仓库执行 git reset --hard HEAD"
echo "  2. 删除所有未跟踪的文件和目录 (git clean -fd)"
echo "  3. 删除所有 .backup 备份文件"
echo ""
echo -e "${RED}  所有未提交的修改将被永久删除！${NC}"
echo ""
echo "============================================================"
echo ""

# 检查 repos 目录是否存在
if [ ! -d "$REPOS_DIR" ]; then
    echo -e "${RED}✗ 错误：repos 目录不存在: $REPOS_DIR${NC}"
    exit 1
fi

# 列出将要还原的仓库
echo "将要还原的仓库："
echo ""
cd "$REPOS_DIR"
repo_count=0
for dir in *; do
    if [ -d "$dir/.git" ]; then
        repo_count=$((repo_count + 1))
        status=$(cd "$dir" && git status --short | wc -l)
        if [ "$status" -gt 0 ]; then
            echo -e "  ${YELLOW}⚠${NC}  $dir (有 $status 处修改)"
        else
            echo -e "  ${GREEN}✓${NC}  $dir (已是干净状态)"
        fi
    fi
done

if [ "$repo_count" -eq 0 ]; then
    echo -e "${YELLOW}  未找到任何 Git 仓库${NC}"
    exit 0
fi

echo ""
echo "共找到 $repo_count 个仓库"
echo ""

# 检查备份文件
backup_count=$(find "$REPOS_DIR" -name "*.backup" -type f 2>/dev/null | wc -l)
if [ "$backup_count" -gt 0 ]; then
    echo -e "${YELLOW}发现 $backup_count 个备份文件将被删除${NC}"
    echo ""
fi

echo "============================================================"
echo ""
read -p "确认执行还原操作？(yes/no): " confirm
echo ""

if [ "$confirm" != "yes" ]; then
    echo -e "${CYAN}已取消操作${NC}"
    exit 0
fi

echo "============================================================"
echo -e "${CYAN}开始还原...${NC}"
echo "============================================================"
echo ""

# 还原所有仓库
restored_count=0
failed_count=0

for dir in *; do
    if [ -d "$dir/.git" ]; then
        echo -e "${CYAN}还原 $dir...${NC}"
        cd "$REPOS_DIR/$dir"
        
        # 执行还原操作
        if git reset --hard HEAD >/dev/null 2>&1 && git clean -fd >/dev/null 2>&1; then
            head_commit=$(git rev-parse --short HEAD)
            echo -e "  ${GREEN}✓${NC} HEAD is now at $head_commit"
            restored_count=$((restored_count + 1))
        else
            echo -e "  ${RED}✗${NC} 还原失败"
            failed_count=$((failed_count + 1))
        fi
        
        cd "$REPOS_DIR"
    fi
done

echo ""

# 删除备份文件
if [ "$backup_count" -gt 0 ]; then
    echo -e "${CYAN}删除备份文件...${NC}"
    find "$REPOS_DIR" -name "*.backup" -type f -delete
    echo -e "  ${GREEN}✓${NC} 已删除 $backup_count 个备份文件"
    echo ""
fi

# 验证结果
echo "============================================================"
echo -e "${CYAN}验证还原结果...${NC}"
echo "============================================================"
echo ""

clean_count=0
dirty_count=0

for dir in *; do
    if [ -d "$dir/.git" ]; then
        cd "$REPOS_DIR/$dir"
        status=$(git status --short)
        if [ -z "$status" ]; then
            echo -e "  ${GREEN}✓${NC}  $dir: 干净"
            clean_count=$((clean_count + 1))
        else
            echo -e "  ${RED}⚠${NC}  $dir: 有未提交修改"
            echo "$status" | head -3 | sed 's/^/      /'
            dirty_count=$((dirty_count + 1))
        fi
        cd "$REPOS_DIR"
    fi
done

echo ""
echo "============================================================"
echo "  还原完成"
echo "============================================================"
echo ""
echo "统计："
echo "  - 还原成功: $restored_count"
echo "  - 还原失败: $failed_count"
echo "  - 最终干净: $clean_count"
echo "  - 仍有修改: $dirty_count"
echo ""

if [ "$dirty_count" -gt 0 ]; then
    echo -e "${YELLOW}⚠ 部分仓库仍有未提交的修改，可能需要手动处理${NC}"
    exit 1
elif [ "$failed_count" -gt 0 ]; then
    echo -e "${YELLOW}⚠ 部分仓库还原失败${NC}"
    exit 1
else
    echo -e "${GREEN}✓ 所有仓库已成功还原到干净状态${NC}"
fi

echo ""
echo "============================================================"
echo -e "${CYAN}还原配置文件 (requirements/*.txt, pyproject.toml)${NC}"
echo "============================================================"
echo ""

# PROJECT_ROOT 已在上面定义
REQUIREMENTS_DIR="${PROJECT_ROOT}/requirements"

# 1. 还原 requirements 目录下的 .txt 文件
echo "正在扫描 $REQUIREMENTS_DIR 下的 .txt 文件..."
# 递归查找 requirements 目录下所有 .txt 文件
mapfile -t REQ_FILES < <(find "$REQUIREMENTS_DIR" -type f -name "*.txt" -print | LC_ALL=C sort)

if [ ${#REQ_FILES[@]} -gt 0 ]; then
    for file in "${REQ_FILES[@]}"; do
        # 获取相对于项目根目录的路径，以便显示
        rel_path="${file#$PROJECT_ROOT/}"
        echo -e "  还原: $rel_path"
        git checkout -- "$file"
    done
else
    echo "  未找到 requirements/*.txt 文件"
fi

# 2. 还原 pyproject.toml
if [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
    echo -e "  还原: pyproject.toml"
    git checkout -- "$PROJECT_ROOT/pyproject.toml"
fi

echo ""
echo -e "${GREEN}✓ 配置文件还原完成${NC}"
