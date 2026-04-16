# Project Instructions

## Project Context

This project uses:
- **Language**: Terraform
- **Pre-Commit Hooks**: pre-commit
- **Dev Environment Tool Manager**: Mise
- **Cloud Provider**: AWS

## File Structure

- `src/` — Terraform root module
- `modules/` — Reusable child modules
- `config/` — TFvars and backend config per environment
- `.claude/` — Claude agents and rules


## Common Commands

```bash
mise run pre-commit # Validate code quality with Pre-Commit

mise run plan-dev # Plan changes in development environment
```

## Rules
Follow patterns under @.claude/rules
