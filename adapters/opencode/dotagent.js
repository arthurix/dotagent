// opencode plugin, maps native opencode events to the dotagent canonical
// events and pipes each payload into .agent/hooks/dispatch.sh. a deny or
// block answer from a pre-tool hook throws, which stops the tool call.
// every directory in .agent/hooks/opencode/ named after a native opencode
// event is registered too, full native surface by mkdir.
import { spawnSync } from "node:child_process"
import { readdirSync } from "node:fs"

const dispatch = (directory, event, payload) => {
  const r = spawnSync(`${directory}/.agent/hooks/dispatch.sh`, [event], {
    input: JSON.stringify(payload ?? {}),
    encoding: "utf8",
    timeout: 15000,
  })
  return { stdout: r.stdout ?? "", stderr: r.stderr ?? "", status: r.status ?? 0 }
}

export const Dotagent = async ({ directory }) => {
  const hooks = {
    "session.created": async () => {
      dispatch(directory, "session-start", {})
    },
    "tool.execute.before": async (input, output) => {
      const r = dispatch(directory, "pre-tool", {
        tool_name: input?.tool ?? "",
        tool_input: output?.args ?? {},
      })
      let parsed
      try { parsed = JSON.parse(r.stdout) } catch { parsed = null }
      const deny = parsed?.hookSpecificOutput?.permissionDecision === "deny"
      if (deny) throw new Error(parsed.hookSpecificOutput.permissionDecisionReason ?? "denied by dotagent hook")
    },
    "tool.execute.after": async (input, output) => {
      dispatch(directory, "post-tool", {
        tool_name: input?.tool ?? "",
        tool_input: output?.args ?? {},
      })
    },
    "session.idle": async () => {
      dispatch(directory, "stop", { stop_hook_active: true })
    },
    "session.deleted": async () => {
      dispatch(directory, "session-end", {})
    },
  }

  let extras = []
  try {
    extras = readdirSync(`${directory}/.agent/hooks/opencode`, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
  } catch {}
  for (const ev of extras) {
    if (ev in hooks) continue
    hooks[ev] = async (input, output) => {
      dispatch(directory, `opencode/${ev}`, { input, output })
    }
  }

  return hooks
}
