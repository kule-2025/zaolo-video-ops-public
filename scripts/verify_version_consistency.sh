#!/usr/bin/env bash
# 版本一致校验脚本
# 校验版本号在 5 处来源的一致性：
#   1. 运行时版本（/api/health）
#   2. 构建版本（pyproject.toml）
#   3. 私有 CHANGELOG
#   4. 公共 CHANGELOG
#   5. Git tag
#
# 用法：bash scripts/verify_version_consistency.sh
# 返回：0 = 全部通过，1 = 存在不一致

set -e
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PASS=0
FAIL=0
SKIP=0

check() {
  local label="$1"
  local actual="$2"
  local expect="$3"
  if [ -z "$actual" ] || [ "$actual" = "SERVER_OFFLINE" ] || [ "$actual" = "NO_TAG" ] || [ "$actual" = "NOT_FOUND" ]; then
    echo "  ⚠️  $label: $actual (跳过)"
    SKIP=$((SKIP+1))
  elif [ "$actual" = "$expect" ]; then
    echo "  ✅ $label: $actual"
    PASS=$((PASS+1))
  else
    echo "  ❌ $label: $actual (期望 $expect)"
    FAIL=$((FAIL+1))
  fi
}

echo "=========================================="
echo "  ZAOLO 造流 · 版本一致校验"
echo "=========================================="
echo ""

# 以 pyproject.toml 为基准版本
EXPECT=$(python -c "import tomllib;print(tomllib.load(open('pyproject.toml','rb'))['project']['version'])" 2>/dev/null || echo "NOT_FOUND")

if [ "$EXPECT" = "NOT_FOUND" ]; then
  echo "❌ 无法读取 pyproject.toml 版本"
  exit 1
fi
echo "基准版本 (pyproject.toml): v$EXPECT"
echo ""

# 1. 运行时版本
RUNTIME=$(curl -s http://localhost:8000/api/health 2>/dev/null | python -c "import sys,json;print(json.load(sys.stdin)['data']['version'])" 2>/dev/null || echo "SERVER_OFFLINE")
check "运行时 /api/health" "$RUNTIME" "$EXPECT"

# 2. 构建版本（已作为基准，跳过重复检查）
echo "  ✅ pyproject.toml: $EXPECT (基准)"
PASS=$((PASS+1))

# 3. 私有 CHANGELOG
PRIV=$(head -30 CHANGELOG.md 2>/dev/null | grep -m1 "^## v" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | sed 's/^v//')
check "CHANGELOG.md" "$PRIV" "$EXPECT"

# 4. 公共 CHANGELOG
PUB=$(head -30 CHANGELOG-PUBLIC.md 2>/dev/null | grep -m1 "^## v" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | sed 's/^v//')
check "CHANGELOG-PUBLIC.md" "$PUB" "$EXPECT"

# 5. Git tag
TAG=$(git tag --points-at HEAD 2>/dev/null | grep -m1 "^v" | sed 's/^v//' || echo "NO_TAG")
check "Git tag" "$TAG" "$EXPECT"

echo ""
echo "=========================================="
echo "  结果: ✅ $PASS 通过  ⚠️ $SKIP 跳过  ❌ $FAIL 失败"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
  echo "❌ 版本不一致，请修复后再发布"
  exit 1
fi

echo "✅ 版本一致，可以继续发布"
exit 0
