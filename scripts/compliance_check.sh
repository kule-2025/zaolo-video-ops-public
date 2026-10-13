#!/usr/bin/env bash
# 公共仓库合规检查脚本
# 检查公共仓库是否包含源码、API 定义、密钥等敏感内容
#
# 用法：
#   bash scripts/compliance_check.sh <public-repo-path>
#   或从项目根目录运行，默认检查公共仓库目录
#
# 返回：0 = 合规，1 = 存在违规

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 公共仓库路径（默认：项目根目录，部署时传参指定）
PUBLIC_DIR="${1:-$PROJECT_DIR}"

echo "=========================================="
echo "  ZAOLO 造流 · 公共仓库合规检查"
echo "=========================================="
echo "目标目录: $PUBLIC_DIR"
echo ""

FAIL=0
PASS=0

pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# ---------- 检查 1：禁止源码文件 ----------
echo "--- 检查 1：禁止源码文件 ---"

# 禁止的源码目录（core/ webapp/ prototype/ 在公共库中不应存在）
for dir in core webapp prototype; do
  if [ -d "$PUBLIC_DIR/$dir" ]; then
    fail "公共仓库包含源码目录: $dir/"
  else
    pass "无源码目录: $dir/"
  fi
done

# 禁止的源码文件扩展名（公共库仅允许文档、品牌、配置元数据）
FORBIDDEN_EXTS=(
  "*.py"
  "*.pyc"
  "*.pyo"
  "*.py[cod]"
)
FOUND_SRC=0
for ext in *.py; do
  if compgen -G "$PUBLIC_DIR/$ext" > /dev/null 2>&1; then
    FOUND_SRC=1
  fi
done
if [ "$FOUND_SRC" -eq 1 ]; then
  # 排除允许的文件（scripts/ 下的工具脚本、__init__.py 如存在）
  SRC_FILES=$(find "$PUBLIC_DIR" -name "*.py" \
    ! -path "*/scripts/*" \
    ! -name "__init__.py" \
    2>/dev/null)
  if [ -n "$SRC_FILES" ]; then
    echo "  发现源码文件:"
    echo "$SRC_FILES" | while read -r f; do echo "    $f"; done
    fail "公共仓库包含 .py 源码文件"
  else
    pass "无 .py 源码文件（仅允许 scripts/ 工具与 __init__.py）"
  fi
else
  pass "无 .py 源码文件"
fi

# ---------- 检查 2：禁止 API 端点定义 ----------
echo ""
echo "--- 检查 2：禁止 API 端点定义 ---"

API_PATTERNS=(
  "/api/health"
  "/api/modules"
  "/api/swarm"
  "/api/rsi"
  "/api/engines"
  "/api/scoring"
  "/api/compliance"
  "/api/production"
  "/api/dataflow"
  "/api/valuechain"
  "/api/pipeline"
  "app.get"
  "app.post"
  "@app\."
  "FastAPI("
  "uvicorn"
)

API_FOUND=0
for pat in "${API_PATTERNS[@]}"; do
  # 在公共文档中搜索（README-PUBLIC, CHANGELOG-PUBLIC, docs/）
  if grep -rqi "$pat" "$PUBLIC_DIR/README-PUBLIC.md" "$PUBLIC_DIR/CHANGELOG-PUBLIC.md" 2>/dev/null; then
    echo "  发现 API 引用: '$pat'"
    API_FOUND=1
  fi
done
if [ "$API_FOUND" -eq 1 ]; then
  fail "公共文档包含 API 端点定义"
else
  pass "公共文档无 API 端点定义"
fi

# ---------- 检查 3：禁止内部架构细节 ----------
echo ""
echo "--- 检查 3：禁止内部架构细节 ---"

ARCH_PATTERNS=(
  "core/"
  "webapp/"
  "prototype/index.html"
  "zaolo_data/"
  "swarm.py"
  "rsi.py"
  "geo.py"
  "scoring.py"
  "compliance.py"
  "production.py"
  "datapipe.py"
  "valuechain.py"
  "pipeline.py"
  "traceability"
  "ui_bindings"
)

ARCH_FOUND=0
for pat in "${ARCH_PATTERNS[@]}"; do
  if grep -qi "$pat" "$PUBLIC_DIR/README-PUBLIC.md" "$PUBLIC_DIR/CHANGELOG-PUBLIC.md" 2>/dev/null; then
    echo "  发现架构引用: '$pat'"
    ARCH_FOUND=1
  fi
done
if [ "$ARCH_FOUND" -eq 1 ]; then
  fail "公共文档包含内部架构细节"
else
  pass "公共文档无内部架构细节"
fi

# ---------- 检查 4：禁止密钥与环境变量 ----------
echo ""
echo "--- 检查 4：禁止密钥与环境变量引用 ---"

SECRET_PATTERNS=(
  "BISU_GH_TOKEN"
  "BISU_GITEE_TOKEN"
  "GH_TOKEN"
  "GITHUB_TOKEN"
  "GITEE_TOKEN"
  "ghp_"
  "gho_"
  "github_pat_"
  "access_token"
  "API_KEY"
  "SECRET_KEY"
  "PRIVATE_KEY"
)

SECRET_FOUND=0
for pat in "${SECRET_PATTERNS[@]}"; do
  if grep -rq "$pat" "$PUBLIC_DIR/README-PUBLIC.md" "$PUBLIC_DIR/CHANGELOG-PUBLIC.md" "$PUBLIC_DIR/LICENSE" 2>/dev/null; then
    echo "  发现密钥引用: '$pat'"
    SECRET_FOUND=1
  fi
done

# 检查是否存在 .env 文件
if [ -f "$PUBLIC_DIR/.env" ]; then
  fail "公共仓库包含 .env 文件"
  SECRET_FOUND=1
fi

if [ "$SECRET_FOUND" -eq 1 ]; then
  fail "公共仓库包含密钥或环境变量引用"
else
  pass "公共仓库无密钥或环境变量引用"
fi

# ---------- 检查 5：禁止令牌硬编码 ----------
echo ""
echo "--- 检查 5：禁止令牌硬编码（全库扫描） ---"

# 在整个公共仓库中扫描令牌模式（ghp_, gho_, gitee token 格式）
TOKEN_PATTERNS=(
  "ghp_[A-Za-z0-9_]{36,}"
  "gho_[A-Za-z0-9_]{36,}"
  "github_pat_[A-Za-z0-9_]{22,}"
  "[a-f0-9]{40}"  # Gitee token 可能是 40 位 hex
)

TOKEN_FOUND=0
for pat in "${TOKEN_PATTERNS[@]}"; do
  if grep -rEq "$pat" "$PUBLIC_DIR" --include="*.md" --include="*.txt" --include="*.toml" --include="*.json" --include="*.yaml" --include="*.yml" 2>/dev/null; then
    echo "  发现疑似令牌: 模式 '$pat'"
    TOKEN_FOUND=1
  fi
done

if [ "$TOKEN_FOUND" -eq 1 ]; then
  fail "公共仓库中发现疑似令牌硬编码"
else
  pass "公共仓库无令牌硬编码"
fi

# ---------- 检查 6：公共库必备文件存在 ----------
echo ""
echo "--- 检查 6：公共库必备文件 ---"

REQUIRED_FILES=(
  "README.md"
  "CHANGELOG.md"
  "LICENSE"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$PUBLIC_DIR/$f" ]; then
    pass "必备文件存在: $f"
  else
    fail "缺少必备文件: $f"
  fi
done

# ---------- 汇总 ----------
echo ""
echo "=========================================="
echo "  结果: ✅ $PASS 通过  ❌ $FAIL 失败"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "❌ 合规检查未通过，请修复以上问题后再发布"
  exit 1
fi

echo ""
echo "✅ 公共仓库合规，可以发布"
exit 0
