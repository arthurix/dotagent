# post-tool

Runs after a tool call returns. Codex also emits this for shell commands with non-zero exit status.

| Client | Native event |
|---|---|
| Claude Code | PostToolUse |
| Codex | PostToolUse |
| OpenCode | tool.execute.after |

## Use it

No logic needed? Drop a `*.md` file here, its content is injected after every tool call, zero code.

For logic, drop an executable and `chmod +x`. Any language. The payload is JSON on stdin, useful fields:

```
.tool_name
.tool_input.file_path
```

Answer with one of:

```bash
exit 0                            # pass, say nothing
echo "some context"               # inject context for the model
echo "what I found" >&2; exit 2   # feed findings back, the model must react
```

The shipped `style_check.sh` here is the exit 2 pattern in action. Copyable skeleton: [../README.md](../README.md#writing-your-own-hook)
