# Claude Code Django — upstream template
#
# Sync .claude/ to a target project:
#   make sync-skills                         # show status (dry run)
#   make sync-skills-apply                   # apply
#   make sync-skills-apply TARGET=/path/to/project
#
# Target project can be set via:
#   - TARGET variable in make
#   - CLAUDE_SYNC_TARGET environment variable
#   - .sync-target file in the repo root

TARGET ?=

.PHONY: sync-skills sync-skills-apply sync-all sync-all-apply

sync-skills:  ## Show sync status without making changes (dry run)
	@bash scripts/sync-to-project.sh $(if $(TARGET),--target "$(TARGET)",)

sync-skills-apply:  ## Sync .claude/ to the target project (skills only)
	@bash scripts/sync-to-project.sh --apply $(if $(TARGET),--target "$(TARGET)",)

sync-all:  ## Dry run: skills + Cursor rules
	@bash scripts/sync-to-project.sh --cursor $(if $(TARGET),--target "$(TARGET)",)

sync-all-apply:  ## Apply: skills + Cursor rules
	@bash scripts/sync-to-project.sh --apply --cursor $(if $(TARGET),--target "$(TARGET)",)
