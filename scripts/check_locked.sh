#!/usr/bin/env bash
# ==========================================
# 锁定检查脚本
# 通过 git diff 检测修改是否触及 [LOCKED] 段落
# 触及则 exit 1
# ==========================================

LOCKED_FILE="LOCKED.md"
MD_FILE="合同文本_Markdown版.md"

# 1. 解析 LOCKED.md 中 [LOCKED] 段落的行号范围
get_locked_line_ranges() {
    local ranges=""
    local in_range=false
    local start_line=""
    local lineno=0

    while IFS= read -r line; do
        lineno=$((lineno + 1))
        if echo "$line" | grep -q '\[LOCKED\]'; then
            start_line=$(echo "$line" | grep -oP 'L\d+')
            # 找到对应的结束行（下一个段落标题或文件结束）
            in_range=true
        elif echo "$line" | grep -qE '^\[(LOCKED|ACTIVE|UNLOCKED)\]' && $in_range; then
            # 下一个段落的开始 = 锁定范围的结束
            ranges="$ranges $start_line"
            in_range=false
        fi
    done < "$LOCKED_FILE"

    # 最后一个锁定的段落到文件末尾
    if $in_range; then
        ranges="$ranges $start_line"
    fi

    echo "$ranges"
}

# 2. 获取 git diff 变更的行号（排除删除的文件）
get_changed_lines() {
    git diff --cached -- "$MD_FILE" 2>/dev/null || git diff -- "$MD_FILE" 2>/dev/null
}

if [ ! -f "$LOCKED_FILE" ]; then
    echo "[check_locked] ⚠️  $LOCKED_FILE 不存在，跳过锁定检查"
    exit 0
fi

if [ ! -f "$MD_FILE" ]; then
    echo "[check_locked] ⚠️  $MD_FILE 不存在，跳过锁定检查"
    exit 0
fi

echo "[check_locked] 检查是否触及 [LOCKED] 段落..."

DIFF_OUTPUT=$(get_changed_lines)

if [ -z "$DIFF_OUTPUT" ]; then
    echo "[check_locked] ✅ 无变更，通过"
    exit 0
fi

# 提取变更行号（从 diff 输出 @@ -a,b +c,d @@ 格式）
CHANGED_LINES=$(echo "$DIFF_OUTPUT" | grep '^@@' | head -20)

if [ -z "$CHANGED_LINES" ]; then
    echo "[check_locked] ✅ 无有效行变更，通过"
    exit 0
fi

# 3. 检查变更行是否落入锁定范围
VIOLATION=false
echo "$CHANGED_LINES" | while IFS= read -r hunk; do
    start_line=$(echo "$hunk" | grep -oP '(?<=-)\d+' | head -1)
    [ -z "$start_line" ] && continue
    echo "  变更起始行: $start_line"
done

# 简化版：检查是否有任何锁定段落
LOCKED_COUNT=$(grep -c '\[LOCKED\]' "$LOCKED_FILE" 2>/dev/null || echo 0)
echo "[check_locked] $LOCKED_COUNT 个段落已锁定"

# 4. 更精确的检查：用 Python 做行号交叉比对
python3 -c "
import re, subprocess, sys

# 读取 LOCKED.md 获取锁定段落的行号范围
locked_ranges = []
try:
    with open('${LOCKED_FILE}', 'r') as f:
        content = f.read()
except FileNotFoundError:
    sys.exit(0)

# 解析锁定段落对应的实际 MD 行号
# 格式: ## 一、服务范围 (L028-L029)
for match in re.finditer(r'L0*(\d+)-L0*(\d+)', content):
    seg_start_line = int(match.group(1))
    seg_end_line = int(match.group(2))
    seg_text = content[match.start():match.start()+200]
    if '[LOCKED]' in seg_text[:200]:
        locked_ranges.append((seg_start_line, seg_end_line))

# 获取 git diff 中的变更行号
result = subprocess.run(['git', 'diff', '--cached', '--', '${MD_FILE}'],
                       capture_output=True, text=True)
if not result.stdout:
    result = subprocess.run(['git', 'diff', '--', '${MD_FILE}'],
                           capture_output=True, text=True)

# 提取变更行 (新的行号)
changed_lines = set()
for m in re.finditer(r'@@ -(\d+),?\d* \+(\d+),?\d* @@', result.stdout):
    new_start = int(m.group(2))
    # 只检查新增行的大致范围
    for offset in range(5):  # 检查从这个hunk开始的5行
        changed_lines.add(new_start + offset)

# 交叉比对
violations = []
for start, end in locked_ranges:
    for cl in changed_lines:
        if start <= cl <= end:
            violations.append((start, end, cl))

if violations:
    print('[check_locked] ❌ 发现越界修改！以下 [LOCKED] 段落被修改：')
    for s, e, cl in violations:
        print(f'  锁定范围 L{s}-L{e}，变更行 {cl}')
    sys.exit(1)
else:
    print('[check_locked] ✅ 所有修改均未触及 [LOCKED] 段落，通过')
"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================
 ❌  锁定检查失败！
 原因：修改了已确认锁定 ([LOCKED]) 的段落。
 解决：
   1. git checkout 合同文本_Markdown版.md 回滚
   2. 或 先将该段落改为 [ACTIVE] 再修改
========================================"
    exit 1
fi

exit 0
