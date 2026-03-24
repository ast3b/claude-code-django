# Claude Code Django — upstream template
#
# Синхронизация .claude/ в целевой проект:
#   make sync-skills                         # показать статус (dry run)
#   make sync-skills-apply                   # применить
#   make sync-skills-apply TARGET=/path/to/project
#
# Целевой проект можно задать:
#   - переменной TARGET в make
#   - переменной окружения CLAUDE_SYNC_TARGET
#   - файлом .sync-target в корне репо

TARGET ?=

.PHONY: sync-skills sync-skills-apply

sync-skills:  ## Показать статус синхронизации (без изменений)
	@bash scripts/sync-to-project.sh $(if $(TARGET),--target "$(TARGET)",)

sync-skills-apply:  ## Синхронизировать .claude/ в целевой проект
	@bash scripts/sync-to-project.sh --apply $(if $(TARGET),--target "$(TARGET)",)
