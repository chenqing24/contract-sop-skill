# 示例构建脚本（通用模板）
# 
# 这是一个参考示例，展示了从 MD + 模板生成 docx 的基本结构。
# 实际使用时，需要根据具体合同的段落索引和内容进行定制。
#
# 核心操作：
# 1. set_para_text(paragraph, "新文本") — 替换段落文字
# 2. p._element.getparent().remove(p._element) — 删除段落（非清空！）
# 3. set_cell_text(cell, "内容") — 更新表格单元格
# 4. del_table_row(row) — 删除表格行（倒序）
#
# 详见 SKILL.md Phase 3 章节。
