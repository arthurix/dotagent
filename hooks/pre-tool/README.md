# pre-tool

Runs before a tool call. The only event that can deny the action.

| Client | Native event |
|---|---|
| Claude Code | PreToolUse |
| Codex | PreToolUse |
| OpenCode | tool.execute.before |

## Use it

No logic needed? Drop a `*.md` file here, its content is injected on every tool call, zero code.

For logic, drop an executable and `chmod +x`. Any language. The payload is JSON on stdin, useful fields:

```
.tool_name
.tool_input.command
.tool_input.file_path
```

Answer with one of:

```bash
exit 0                # pass, say nothing
echo "some context"   # inject context for the model
```

or block the call (first deny in this directory wins):

```bash
jq -cn '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "why"}}'
```

Copyable skeleton with all of this filled in: [../README.md](../README.md#writing-your-own-hook)
