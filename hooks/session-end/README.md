# session-end

Runs when the session terminates. Ships empty.

| Client | Native event |
|---|---|
| Claude Code | SessionEnd |
| Codex | SessionEnd (advisory; output cannot keep the session open) |
| OpenCode | session.deleted |

## Use it

Drop an executable and `chmod +x`. Any language. The payload is JSON on stdin.

There is no model to talk to anymore, output goes nowhere. Good for cleanup and logging:

```bash
#!/bin/bash
date >> .agent/session.log
```

Copyable skeleton: [../README.md](../README.md#writing-your-own-hook)
