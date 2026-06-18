---
name: contract-sop
description: |
  合同修改的防御性工作流。当用户需要逐段修改一份已有合同时触发——甲方发来草案、乙方版本回改、多轮谈判修改。
  核心问题：防止AI冲动式大改 / 改完忘记改了什么 / 后续反复踩已确认条款。
  核心方法：Markdown-first提取 → Git逐段锁定 → 双脚本硬阻断 → 最后回填docx。
  触发词："修改合同"、"逐段改合同"、"合同改稿"、"甲方批注"、"谈判修改"、"contract review"、"revise contract"。
  不触发：从零起草全新合同（非基于已有文档修改）、PDF/图片格式转换、排版格式调整、合同审计/审查（本技能仅处理修改，审计请用 huashu-doc-reviewer 专家）。
version: 2.2.1
agent_created: true
---

# 合同修改防御性工作流

## 它解决什么问题

拿到一份待修改的合同（甲方发来的草案、旧版合同、标注版合同），AI 拿到文档后最常见的灾难：

| 问题 | 表现 |
|------|------|
| **冲动式大改** | 一次性改几十处，用户根本看不过来 |
| **忘记改了什么** | 改完后用户问"第三条第2款你改了什么"，完全答不上来 |
| **反复踩已确认条款** | 后续对话中又动了用户已经确认过的段落 |
| **格式炸裂** | 复制粘贴到 docx 后排版面目全非 |

**这个工作流用一套机械化的流程，把这些风险锁死。**

核心设计思想：**每次只改一小块，改了立刻锁定，锁定有脚本强制执行。**

## 适用场景

- 甲方发来合同草案，需要逐条修改谈判
- 有多个决策点需要在合同中逐段落实
- 合同长度超过5页，涉及金额/工期/技术栈/违约等多字段交叉
- 修改周期跨多天，需要防止遗忘已确认内容

### 典型会话示例

```
用户: "甲方发来了标注版合同，帮我逐段修改"
→ Phase 0: 提取 docx 为 MD，发现 comments.xml 有 5 条批注
→ Phase 1: git init, 创建 LOCKED.md, 设置 check 脚本
→ Phase 2: 从封面开始逐段确认——用户说"改合同名"→改一段→check→commit→锁
→ ...14 段全部确认...
→ Phase 3: 运行构建脚本，回填到 docx
→ Phase 3.5: 全文通读发现页眉还是旧名→修复→重新生成
→ Phase 4: 自检全通过 → 交付
```

## 四阶段流程

### Phase 0：提取 → 拿到纯文本版本

**目标**：把 docx 的复杂格式剥离掉，得到一份干净的 MD 文件。

1. 将现有合同 docx 内容提取为 `合同文本_Markdown版.md`
2. **如客户通过 Word 批注提供意见**，必须同时读取 `word/comments.xml` 中的批注内容并映射到对应段落
3. docx 中的格式信息（字体、字号、页边距）暂时搁置——后期通过模板回填解决
4. 标注所有决策点、争议条款的段落位置

```python
# 快速提取
from docx import Document
doc = Document("甲方合同.docx")
for i, p in enumerate(doc.paragraphs):
    if p.text.strip():
        print(f"P{i:03d}: {p.text}")
```

**输出**：一份纯文本 MD + 段落索引 → 内容映射表

### Phase 1：建防修改体系

**目标**：建立三道防线，确保改不乱、改不错、改不丢。

#### 1.1 Git 仓库

```bash
cd <项目目录>
git init
echo '*_v*.docx' >> .gitignore
echo '*.reviewed.docx' >> .gitignore
git add 合同文本_Markdown版.md .gitignore
git commit -m "初始: 甲方合同草案"
```

> **若环境不支持 git**：用 `.backup/` 目录 + 时间戳文件名替代版本管理。LOCKED.md 改为手工追加修改记录（格式：`日期 | 段落 | 修改内容`）。

#### 1.2 LOCKED.md —— 段落状态机

从 `references/LOCKED.md.template` 复制，填写每个段落在 MD 中的行号范围。

每个段落三种状态：

| 状态 | 含义 | 谁可改 |
|------|------|--------|
| `[UNLOCKED]` | 还没轮到 | 无人 |
| `[ACTIVE]` | 当前正在改 | AI + 用户 |
| `[LOCKED]` | 已确认冻结 | 只有用户明确说"回前面改"才能动 |

**铁律**：同一时间只能有 1 个 `[ACTIVE]`。

#### 1.3 check_locked.sh —— 硬阻断

```bash
cp scripts/check_locked.sh <项目>/scripts/
```

此脚本通过 `git diff` 检测修改行号是否落入 `[LOCKED]` 段落范围。落入 → `exit 1` 强制阻断。

> macOS 上脚本依赖内置的 Python fallback（第 84 行），不依赖 GNU grep。

#### 1.4 check_contract.sh —— 数据自检

从 `references/check_contract.sh.template` 复制，填充当前合同的关键数据字段。

三类检查：
- **应出现项**：金额、税率、工期、技术栈等关键字段
- **应删除项**：所有旧版本的值
- **数量检查**：特定字段出现次数（如"合同有效期"恰好1处）

### Phase 2：逐段修改 + 锁定

这是核心环节。每一段的修改流程完全相同：

```
① 用户明确第 N 段要改什么
② 只改 合同文本_Markdown版.md 的当前段（不改其他任何段落）
③ git diff --stat 确认只动了当前段落
④ bash scripts/check_locked.sh    ← 硬阻断（确认没踩锁定段）
⑤ bash scripts/check_contract.sh  ← 数据自检
⑥ git commit -m "确认: 第N段 — 修改摘要"
⑦ LOCKED.md: 当前段 [ACTIVE]→[LOCKED]，下一段 [UNLOCKED]→[ACTIVE]
⑧ 自检脚本基线同步更新（当前段新增的检查项加入 check_contract.sh）
⑨ 进入第N+1段
```

**为什么必须是这个顺序？**

- 步骤④在前：防止错误假设。本来以为改的是"服务范围"，结果不小心动到了已经锁定的"资费标准"——立即阻断，不让你 commit。
- 步骤⑤在后：内容级验证。LOCKED 检查过了不代表数据没问题。
- 步骤⑧是关键：每确认一段，`check_contract.sh` 的检查基线就新增这一段的关键字段。这样越往后，自检越严格，越不可能出错。

**失败处理**：

若步骤④ (check_locked) 或步骤⑤ (check_contract) 失败：
1. 报告用户**哪个锁定段被拦截**（check_locked）或**哪项检查未通过**（check_contract）
2. 回退到步骤②（重新修改当前段）
3. 重新执行步骤③④⑤
4. 同一段最多重试 **3 次**；第 4 次失败 → 中断并向用户报告「无法自动修复，请手动检查」

### Phase 3：回填到 docx

**目标**：把 MD 内容灌入模板 docx，保留格式，输出正式版。

> ⚠️ **`scripts/md_to_docx.py` 为通用模板**，需根据实际合同的段落索引、表格结构调整后方可使用。参考 `references/example_build_script.py` 了解构建脚本的基本结构。

```bash
python3 scripts/md_to_docx.py 模板.docx 合同文本_Markdown版.md 正式版.docx
```

**操作分类**：

| 操作 | 方法 | 注意 |
|------|------|------|
| 修改文本 | `set_para_text(para, text)` | 替换 runs 文字，保留格式 |
| 删除段落 | `p._element.getparent().remove(p._element)` | **绝不能**用 `run.text = ''`（会留空白） |
| 删除表格行 | `row._element.getparent().remove(row._element)` | 倒序删除 |
| 更新表格 | `set_cell_text(cell, text)` | 保留单元格格式 |

**关键教训**：`run.text = ''` 看起来像是"删除"，实际是"留了个空壳"。Word 打开后会显示大段空白。

**基于客户批注版生成时必须额外清理**：
如果修改源是客户批注版 docx，生成后必须：
```python
# 1. 删除评论相关文件
import zipfile, re
with zipfile.ZipFile("正式版.docx") as zin:
    with zipfile.ZipFile("clean.docx", "w") as zout:
        for item in zin.namelist():
            if "comment" in item.lower() or "people" in item.lower():
                continue
            data = zin.read(item)
            # 2. 修复 [Content_Types].xml 中的引用
            if item == "[Content_Types].xml":
                data = re.sub(rb"<Override[^>]*comments[^>]*/>", b"", data)
                data = re.sub(rb"<Override[^>]*people[^>]*/>", b"", data)
            # 3. 修复 document.xml.rels 中的引用
            if "document.xml.rels" in item:
                data = re.sub(rb"<Relationship[^>]*comments[^>]*/>", b"", data, re.I)
                data = re.sub(rb"<Relationship[^>]*people[^>]*/>", b"", data, re.I)
            zout.writestr(item, data)
```

### Phase 3.5：全文通读排错 🔍

**这是最容易跳过的步骤，也是出问题最多的步骤。**

docx 生成后，无论多自信，必须逐段通读一遍生成的 docx 全文，逐个检查：

1. **段落顺序** — 新增/插入的段落是否在正确位置？`insert_para_after()` 多次调用会逆序插入
2. **条款完整性** — 是否有多条条款因插入操作被挤压丢失？
3. **空段落检查** — 连续空段落是否超过 2 个？
4. **表格行数** — 是否有多余的空数据行未删除？
5. **关键字段逐项验证** — 金额、税率、工期、大写金额、管辖地
6. **残留批注清除** — 如果基于甲方批注版生成，必须删除 comments.xml 等批注文件
7. **页眉页脚** — 合同名称修改后，页眉页脚中的旧名称可能残留，需单独检查并替换

```python
# 快速全文输出
from docx import Document
doc = Document("正式版.docx")
for i, p in enumerate(doc.paragraphs):
    t = p.text.strip()
    if t:
        print(f"P{i:03d}: {t}")
```

**铁律：不经过人工/模型全文通读的 docx，不算完成。**

#### docx 操作常见陷阱（实战教训）

| 陷阱 | 表现 | 正确做法 |
|------|------|----------|
| **客户批注藏在 comments.xml 中** | 对比正文内容发现"没改"，实际客户在 Word 里加了批注气泡 | 读取客户 docx 时，同时检查 `word/comments.xml` 中的批注内容，并将其映射到对应段落 |
| **删除 comments.xml 导致文件损坏** | `zipfile` 直接删文件，python-docx 无法打开 | 删除 comments/people 文件后，必须同步清除 `[Content_Types].xml` 中的 Override 引用和 `word/_rels/document.xml.rels` 中的 Relationship 引用 |
| **页眉/页脚是独立 XML** | 改名后正文已更新，打印出来页眉依然是旧名称 | 合同名称变更时，必须搜索并替换 `word/header*.xml` 和 `word/footer*.xml` 中的旧名称 |
| **`insert_para_after()` 逆序插入** | 多次调用 `element.addnext()` 插入多个段落时，第一个插入的被后续插入挤到最远处 | 插入多个段落时按**逆向顺序**调用，或改用正序方案（先插最远的） |
| **空段落 `set_para_text` 静默失败** | 段落没有 `<w:r>` 元素时，`para.runs` 为空导致写入无效 | 对无 run 的段落使用 lxml 直接创建 `<w:r><w:t>` 元素 |

### Phase 4：最终验证

```bash
# 数据完整性
bash scripts/check_contract.sh

# OOXML 命名空间（必须全 w: 标签，无 ns0:）
python3 -c "
import zipfile, re
with zipfile.ZipFile('正式版.docx') as z:
    xml = z.read('word/document.xml').decode()
    print(f'ns0: tags = {len(re.findall(r\"<ns0:\", xml))}')
    print(f'w: tags = {len(re.findall(r\"<w:\", xml))}')
"
```

## 为什么这个流程对合同修改有效

| 传统做法 | 这个流程 |
|----------|----------|
| AI 一眼扫完整份合同，直接输出修改版 | 必须逐段确认，每次只改一小块 |
| 用户不知道改了什么，要逐字比对 | `git log` 每笔 commit 精确到段 |
| 一周后忘记第三条第2款为什么这么写 | `git blame` 指向当时的 commit message |
| AI 后续对话中又不小心改了回去 | `check_locked.sh` 硬阻断 |
| 改到一半发现金额不对 | `check_contract.sh` 每次都全量自检 |

## 项目目录结构

```
<合同项目目录>/
├── 合同文本_Markdown版.md    ← ✅ git ─ 唯一内容源，逐段修改
├── 甲方合同_vN.docx          ← ❌ 忽略 ─ 甲方原版，只读
├── 模板_vM.docx              ← ❌ 忽略 ─ 格式底本，只读
├── LOCKED.md                 ← ✅ git ─ 锁定状态机
├── .gitignore                ← ✅ git
├── scripts/
│   ├── check_contract.sh     ← ✅ git ─ 逐步累积的检查基线
│   ├── check_locked.sh       ← ✅ git
│   └── md_to_docx.py         ← 可选
└── 正式版.docx               ← ❌ 忽略 ─ 最终输出
```
