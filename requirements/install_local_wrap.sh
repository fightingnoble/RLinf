#!/bin/bash
# 统一的安装与验证脚本（Docker/本地均可复用）
set -e

# 运行前需确保：
# - 已处于仓库根目录
# - external_repo 等环境变量已设置（由调用方负责）

echo "[Wrap] 清理缓存与虚拟环境..."
uv cache clean || true
rm -rf .venv uv.lock pyproject.toml.backup requirements/*.backup

echo "[Wrap] 运行 prepare 阶段（安装 Python 3.11）..."
sudo --preserve-env=external_repo bash requirements/install.sh prepare --python /usr/bin/python3.11
echo ""

echo "[Wrap] 运行 embodied 安装..."
echo '========================================'
echo 'Embodied Installation'
echo '========================================'
echo 'Environment:'
echo "  external_repo: $external_repo"
echo '  Python: /usr/bin/python3.11'
echo ''
sudo --preserve-env=external_repo bash requirements/install.sh embodied --model openvla --env maniskill_libero --python /usr/bin/python3.11 2>&1 | tee /tmp/install_full.log
echo ""

echo "[Wrap] 验证安装结果..."
echo '============================================================'
echo '  关键依赖来源检查'
echo '============================================================'
echo ''

echo '【🟢 本地 Git 仓库使用】'
grep -E '\[local-deps\] using local repo' /tmp/install_full.log | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  ✓ /' || echo '  (未找到)'
echo ''

echo '【🟢 本地 Wheel 使用】'
grep -E '\[local-deps\] using local wheel' /tmp/install_full.log | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  ✓ /' || echo '  (未找到)'
echo ''

echo '【🟡 远程回退（应尽量为空）】'
grep -E '\[local-deps\] remote (fallback|wheel fallback)' /tmp/install_full.log | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  ⚠ /' || echo '  ✓ 无远程回退'
echo ''

echo '【本地路径复制】'
grep 'Using local repository' /tmp/install_full.log | sed 's/^/  ✓ /' || echo '  (未找到)'
echo ''

echo '【ManiSkill Assets】'
grep 'ManiSkill assets' /tmp/install_full.log | sed 's/^/  /' || echo '  (未找到)'
echo ''

echo '【🔵 备份还原】'
grep -E '\[local-deps\] restoring' /tmp/install_full.log | sed 's/\x1b\[[0-9;]*m//g' | tail -5 | sed 's/^/  /' || echo '  (未找到)'
echo ''

echo '============================================================'
echo '  PyPI 下载统计'
echo '============================================================'
grep 'Downloading' /tmp/install_full.log | wc -l | xargs echo '  PyPI 包下载数量:'
echo ''

echo '============================================================'
echo '  安装的关键包版本'
echo '============================================================'
source .venv/bin/activate
pip show openvla dlimp mani-skill libero 2>/dev/null | grep -E '(Name|Version|Location):' | sed 's/^/  /'
echo ""

