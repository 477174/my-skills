<!-- Paste into the project's AI instruction file: CLAUDE.md, AGENTS.md,
     .cursorrules, or .github/copilot-instructions.md -->

## Development URLs

This project runs multiple git worktrees simultaneously; each has unique
nip.io hostnames and ports. **Never assume `localhost:PORT`.**

When the dev environment is running (`make dev`), the correct URLs for THIS
worktree are written to `.dev-urls` in the worktree root. Always read it first:

```
cat .dev-urls
# FRONTEND_URL=http://my-project-feature-auth-frontend.127.0.0.1.nip.io
# API_URL=http://my-project-feature-auth-api.127.0.0.1.nip.io
# API_DOCS=http://my-project-feature-auth-api.127.0.0.1.nip.io/docs
```

Use those URLs for browsing the app, hitting the API, and integration tests.
`make ports` prints the same values plus the raw host ports.
