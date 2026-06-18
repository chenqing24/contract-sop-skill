# contract-sop

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) | [Skill评估: A⁺ (8.70/10)](https://github.com/sunxingboo/skill-evaluator)

一个将 AI 合同修改流程**机械化、防出错、可追溯**的 WorkBuddy Skill。让每次合同谈判修改都像律师改稿一样严格执行审阅→修改→锁定→验证流程。

兼容所有支持 Skill 机制的 AI Agent 平台，包括但不限于 Claude Code、WorkBuddy、Ducc、小龙虾等。

## 它解决什么问题

AI 修改合同最常见的灾难：

| 问题 | 表现 |
|------|------|
| **冲动式大改** | 一次性改几十处，用户根本看不过来 |
| **忘记改了什么** | 改完后用户问"第三条第2款你改了什么"，完全答不上来 |
| **反复踩已确认条款** | 后续对话中又动了用户已经确认过的段落 |
| **格式炸裂** | 复制粘贴到 docx 后排版面目全非 |

## 特性

- **四阶段锁定流程** — Phase 0: 提取 → Phase 1: 建防修改体系 → Phase 2: 逐段锁定 → Phase 3: 回填 docx
- **Git 逐段锁定** — 每次只改一段，改完立刻 commit + 锁定，`git blame` 可追溯到每个字的修改原因
- **双脚本硬阻断** — `check_locked.sh` 防止踩已确认段落，`check_contract.sh` 全量数据自检
- **Phase 3.5 通读排错** — 5 个 docx 实战陷阱（批注残留、文件损坏、页眉独立、逆序插入、空段落失败）
- **端到端会话示例** — 典型 14 段合同修改完整流程演示

## 评估等级

由 [skill-evaluator](https://github.com/sunxingboo/skill-evaluator) 独立评估：

| 版本 | 分数 | 等级 | 评估日期 |
|------|------|------|----------|
| v2.2.1 | 8.70 | **A⁺** (优秀) | 2026-06-18 |

评估报告详情：D1-D4 均 9 分（元数据/执行引导/领域知识/工作流），D5-D7 均 8 分（输入输出/资源利用/写作质量），D8 范围聚焦 9 分。

## 快速开始

### 安装

```bash
# WorkBuddy 托管式安装
workbuddy skill install contract-sop --from github:chenqing24/contract-sop-skill

# 或手动克隆
git clone git@github.com:chenqing24/contract-sop-skill.git ~/.workbuddy/skills/contract-sop
```

### 触发方式

在 WorkBuddy 对话中说出以下关键词即可触发：

- "修改合同"
- "逐段改合同"
- "合同改稿"
- "甲方批注"
- "谈判修改"

**不会触发**：从零起草合同、PDF/图片格式转换、合同审计/审查（请用 huashu-doc-reviewer 专家）

### 典型会话

```
用户: "甲方发来了标注版合同，帮我逐段修改"
→ Phase 0: 提取 docx 为 MD，自动发现 comments.xml 中的 5 条批注
→ Phase 1: git init → LOCKED.md → check 脚本部署
→ Phase 2: 逐段确认修改，每段只改一处 → commit → 锁定
→ Phase 3: MD 回填到 docx，自动清理客户批注残留
→ Phase 3.5: 全文通读发现页眉还是旧名 → 修复 → 重新生成
→ Phase 4: 42/42 自检通过 → 交付甲方
```

## 文件结构

```
contract-sop/
├── SKILL.md                          # 核心技能定义
├── README.md                         # 本文件
├── .gitignore
├── scripts/
│   ├── check_locked.sh               # 段落锁定硬阻断脚本
│   └── md_to_docx.py                 # MD→docx 回填工具（模板）
└── references/
    ├── LOCKED.md.template            # 段落锁定状态机模板
    ├── check_contract.sh.template    # 数据自检脚本模板
    └── example_build_script.py       # docx 构建脚本示例
```

## 适用场景

- 甲方发来合同草案，需要逐条修改谈判
- 有多个决策点（金额/工期/技术栈/违约等）跨字段交叉影响
- 合同超过 5 页，修改周期跨多天，需要防止遗忘已确认内容
- 处理客户通过 Word 批注功能标注的修改意见

## 许可证

MIT License — 详见 [LICENSE](LICENSE)
