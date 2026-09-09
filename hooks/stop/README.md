# stop

Runs when the model tries to finish its turn.

| Client | Native event |
|---|---|
| Claude Code | Stop |
| Codex | Stop |
| OpenCode | session.idle |

## Use it

No logic needed? Drop a `*.md` file here, its content is injected at every turn end, zero code.

For logic, drop an executable and `chmod +x`. Any language. The payload is JSON on stdin, useful fields:

```
.stop_hook_active
.transcript_path
```

Answer with one of:

```bash
exit 0                # let the turn end
echo "some context"   # inject context
```

or refuse the turn end and send the model back to work (first block wins):

```bash
jq -cn '{decision: "block", reason: "why the model cannot stop yet"}'
```

The shipped save gate here is the block pattern in action. Copyable skeleton: [../README.md](../README.md#writing-your-own-hook)
