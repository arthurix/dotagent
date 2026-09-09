# prompt-submit

Runs before the model processes a user prompt.

| Client | Native event |
|---|---|
| Claude Code | UserPromptSubmit |
| Codex | UserPromptSubmit |
| OpenCode | not emitted, no equivalent event |

## Use it

No logic needed? Drop a `*.md` file here, its content rides with every prompt, zero code. Strongest instruction channel there is, it can never fall out of context.

For logic, drop an executable and `chmod +x`. Any language. The payload is JSON on stdin, useful field:

```
.prompt
```

Answer with one of:

```bash
exit 0                # say nothing
echo "some context"   # injected into the model's context with the prompt
```

Copyable skeleton: [../README.md](../README.md#writing-your-own-hook)
