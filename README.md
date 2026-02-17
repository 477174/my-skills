# my-skills

Collection of AI coding skills for Claude Code, Cursor, OpenCode, and other AI agents.

## Skills

| Skill | Description |
|-------|-------------|
| [semantic-prompt-craft](./skills/semantic-prompt-craft/SKILL.md) | Methodology for designing LLM system prompts that maximize behavioral effectiveness without creating bias. Covers identity framing, negative boundaries, anti-bias patterns, and small-model optimization. |

## Installation

### Via SkillsMP CLI

```bash
skillsmp install 477174/my-skills --skills semantic-prompt-craft --agents claude-code
```

### Manual

Copy the desired `SKILL.md` file into your agent's skills directory:

- **Claude Code**: `.claude/skills/<skill-name>/SKILL.md`
- **OpenCode**: `.opencode/skills/<skill-name>.md`
- **Cursor**: `.cursor/skills/<skill-name>.md`

## License

MIT
