# session-start

Runs when a session begins or resumes.

| Client | Native event |
|---|---|
| Claude Code | SessionStart |
| Codex | SessionStart |
| OpenCode | session.created |

## Use it

No logic needed? Drop a `*.md` file here, its content is injected at every session open, zero code.

For logic, drop an executable and `chmod +x`. Any language. The payload is JSON on stdin.

Answer with one of:

```bash
exit 0                # say nothing
echo "some context"   # injected as startup context
```

The shipped `session_restore.sh` here prints the whole memory snapshot this way. Copyable skeleton: [../README.md](../README.md#writing-your-own-hook)
