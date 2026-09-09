# Hooks

Two mechanisms keep the agent on track between and during sessions:

1. **The rules table** in `memory.db`, injected into every prompt. Data, not code: add or disable a rule with one SQL statement, no restart.
2. **Hook scripts**, executables run on harness events (prompt submitted, tool about to run, turn ending). They inject context or block actions mechanically, so discipline does not depend on the model remembering.

## The layout, one directory per event

Everything lives in `.agent/hooks/` in your project, installed by `install/*`. The event names are dotagent's own, tool neutral; each tool's installer maps its native events onto them, so the hooks themselves never care which client is running.

```
.agent/hooks/
├── dispatch.sh                shared canonical event dispatcher
├── codex.sh                   installed Codex payload adapter
├── session-start/
│   ├── session_restore.sh
│   └── session_restore_instructions.json
├── prompt-submit/
│   ├── feedback_capture.sh
│   ├── feedback_capture_instructions.json
│   └── rules_inject.sh
├── pre-tool/
│   ├── code_style_reminder.sh
│   ├── code_style_reminder_instructions.json
│   ├── commit_style_check.sh
│   ├── commit_style_check_instructions.json
│   ├── pr_style_reminder.sh
│   └── pr_style_reminder_instructions.json
├── post-tool/
│   └── style_check.sh
├── stop/
│   ├── memory_save_check.sh
│   └── memory_save_check_instructions.json
├── session-end/               ships empty, drop a script in
├── claude/                    full native Claude Code surface, claude/<Event>/
├── codex/                     six events outside the shared set, codex/<Event>/
└── opencode/                  full native OpenCode surface, opencode/<event>/
```

The directory name is the event, so the layout answers "when does this run". `dispatch.sh <event>` runs everything executable in `<event>/` in lexical order, run-parts style: the exec bit is the on switch, prefix with numbers (`10-lint.sh`, `20-style.py`) to control order, `chmod -x` to disable a hook without deleting it. Any language works, a hook reads the event payload as JSON on stdin (Claude Code's payload shape is the contract, adapters for other tools synthesize it).

**Adding a hook after install:**

```bash
cp custom.py .agent/hooks/pre-tool/ && chmod +x .agent/hooks/pre-tool/custom.py
```

That is the whole procedure. No installer, no settings edit, next event fires it.

**Instructions without code:** any `*.md` file in an event directory (README.md excluded) is standing instructions, its content is injected as context every time the event fires. "Always tell the AI this on pre-tool" is one dropped md file, scripts are only for hooks that compute something.

Merging, when several hooks answer the same event: the first deny or block wins and short-circuits, context outputs concatenate into one, an exit code 2 with stderr is forwarded so a check hook can feed findings back to the model.

## The events and what calls them

The dispatcher is plain shell reading stdin, tool agnostic. Each tool's installer wires its native events to the canonical ones:

| dotagent event | Claude Code | Codex | OpenCode (plugin) |
|---|---|---|---|
| `session-start` | SessionStart | SessionStart | session.created |
| `prompt-submit` | UserPromptSubmit | UserPromptSubmit | — |
| `pre-tool` | PreToolUse | PreToolUse | tool.execute.before |
| `post-tool` | PostToolUse | PostToolUse | tool.execute.after |
| `stop` | Stop | Stop | session.idle |
| `session-end` | SessionEnd | SessionEnd | session.deleted |

Each canonical directory carries its own README with this mapping, the payload fields and the answer format for that event.

Committed to one client? Its full native surface is there too, namespaced per client so vocabularies never mix:

- **Claude Code**: `install/claude` wires the six canonical events plus every `claude/<Event>` directory into `.claude/settings.json`, and all native events from the [docs](https://code.claude.com/docs/en/hooks) ship pre-created (e.g. `claude/CwdChanged`), so dropping a script into any of them needs zero further steps. A future event is `mkdir .agent/hooks/claude/<Event>` plus re-run, the wiring loop reads the directories.
- **OpenCode**: `install/opencode` ships a plugin (`.opencode/plugins/dotagent.js`) that pipes its native events into the dispatcher and turns a `deny` answer from a pre-tool hook into a thrown error that stops the tool call. All native events from [their docs](https://opencode.ai/docs/plugins/) ship pre-created under `opencode/` (e.g. `opencode/session.error`), the plugin registers every directory it finds at load. Experimental, not exercised end to end.
- **Codex**: `install/codex` wires all twelve events into `.codex/hooks.json`: six use the shared canonical directories, while `PermissionRequest`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`, and `Interrupt` have directories under `codex/`. Those six are outside dotagent's shared event set; the shared events are not duplicated in this folder. Native directories ship empty and accept executable scripts with the original Codex payload; their JSON decisions are preserved. See the [official hook contract](https://learn.chatgpt.com/docs/hooks), verified against CLI `0.153.4` on 2026-09-09. New or changed definitions require review through `/hooks`, and project configuration must be trusted.
- **Gemini CLI and AGENTS.md-native tools**: no hook runtime. `AGENTS.md` and the RESTORE-time load of the `rules` table carry the same instructions, enforced by the model instead of the harness.

**The ceiling, honestly.** Events are born inside the client: a hook fires because the client's own code calls its hook system at that moment, so an adapter can only translate events a client already emits, never invent emission points in someone else's binary. And a hook is only worth having where its answer has a channel back into the model (inject context, deny the action). That is why the canonical six are the portable intersection, the per-client namespaces carry each client's full surface inside that client only, and a union across clients is impossible without the vendors shipping the events themselves.

## The rules hook

`prompt-submit/rules_inject.sh` prints the active `rules` rows from `memory.db` on every prompt. Whatever a prompt-submit hook prints is added to the model's context, which makes `rules` rows the strongest instruction channel you have, they cannot fall out of a long session's context.

### Managing rules

```bash
# add a rule
sqlite3 .agent/memory.db "INSERT INTO rules (name, content) VALUES ('response-style', 'RESPONSE STYLE (hook enforced): short, direct, no filler, code first.')"

# see what is active
sqlite3 -header -column .agent/memory.db "SELECT name, active, substr(content,1,80) FROM rules"

# disable / re-enable without losing the text
sqlite3 .agent/memory.db "UPDATE rules SET active=0 WHERE name='response-style'"
sqlite3 .agent/memory.db "UPDATE rules SET active=1 WHERE name='response-style'"

# update
sqlite3 .agent/memory.db "UPDATE rules SET content='...', updated_at=datetime('now') WHERE name='response-style'"

# remove
sqlite3 .agent/memory.db "DELETE FROM rules WHERE name='response-style'"
```

Keep rules short and imperative. One topic per row. A prefix like `RESPONSE STYLE (hook enforced, non negotiable):` tells the model the rule is mechanical, not a suggestion.

## Writing your own hook

A hook reads a JSON payload on stdin (`.tool_input.command`, `.tool_input.file_path`, `.tool_name`, ...) and can respond three ways:

- print plain text or JSON with `additionalContext` to add context:
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"..."}}`
- print JSON with `permissionDecision: "deny"` (pre-tool) or `decision: "block"` (stop) to block the action with a reason the model sees
- exit with code 2 after printing to stderr, the harness feeds stderr back to the model

There are no matchers, a hook filters itself: check `.tool_name` or the command/file in the payload and `exit 0` when it does not apply, like the shipped hooks do.

The whole contract as one copyable skeleton. Save it in the event directory whose README matches the moment you care about, `chmod +x`, done:

```bash
#!/bin/bash
# what this hook does, one line

# the event payload arrives as json on stdin, read it once
payload="$(cat)"

# fields you can pull from it (see the event directory README for the full list)
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""')"

# respect the /dotagent off switch like every shipped hook
[ "$(sqlite3 "${CLAUDE_PROJECT_DIR:-.}/.agent/memory.db" "SELECT value FROM state WHERE key='dotagent'" 2>/dev/null)" = "off" ] && exit 0

# filter yourself, exit 0 silently when this event is not your business
case "$cmd" in
  *"rm -rf"*) ;;
  *) exit 0 ;;
esac

# then answer in exactly one of three ways

# 1. block the action with a reason the model sees (pre-tool only, stop uses {"decision":"block","reason":"..."})
jq -cn '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "no recursive deletes, remove files explicitly"}}'
exit 0

# 2. or inject context instead of blocking
# jq -cn --arg s "some standing instruction" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $s}}'

# 3. or feed findings back to the model
# echo "what I found" >&2 && exit 2
```

If the text you inject should be editable without touching code, put it in a `<script>_instructions.json` next to the script and read it with `jq -r '.style // ""' "$conf"`, the shipped hooks show the pattern. And when the hook has no logic at all, skip the script entirely, a `*.md` file in the event directory injects its content every time.

## The instructions jsons

Customizing never means editing a script. Every script reads a `<script>_instructions.json` neighbor holding its data. Keys per hook: `pr_style_reminder` has `style`, `commit_style_check` has `style` plus one `deny_*` text per mechanical check, `feedback_capture` has `pattern` (regex) and `context`, `memory_save_check` has `reason`, `session_restore` has `off` and `footer`. Two are structured: `code_style_reminder_instructions.json` is an ordered list of `{globs, style}` entries (first match wins, empty style skips the file), `style_check_instructions.json` is a list of `{pattern, message, glob?}` checks grepped against added lines, add your project's banned patterns there. Only commit_style_check's check SET is code, its texts are json.

## How the save enforcement works

`feedback_capture.sh` writes a UTC timestamp to `.agent/.last_prompt` on every prompt. When the model tries to finish a turn, `memory_save_check.sh` compares: if `memory.db` was not modified after the marker AND the turn used Edit/Write, it blocks with a reason telling the model to classify and save per AGENTS.md. The `stop_hook_active` guard means it blocks at most once per turn, so the model can answer "nothing worth saving" and stop. Claude sessions share the prompt marker, so several windows can cause a spurious nudge.

For Codex, the adapter supplies `DOTAGENT_PROMPT_MARKER` and `DOTAGENT_EDIT_MARKER` under `.agent/.codex-turns/`, scoped by session and turn. `PostToolUse` for `apply_patch` marks edit activity; the save gate uses that marker instead of reading an unstable Codex transcript format. Shell commands that edit files are outside this edit detector. The database modification time is still shared across sessions. `SessionEnd` removes that session's markers; interrupted or crashed sessions may leave them behind. Reinstalling preserves existing hook scripts: older installations must merge the marker-variable changes in `feedback_capture.sh` and `memory_save_check.sh` to enable Codex save enforcement.

Codex reports shell calls as `Bash` and patches as `apply_patch`. The adapter extracts all add/update/delete/move paths from `tool_input.command` and supplies absolute `tool_input.file_path` values to the canonical style hooks. Canonical hooks run first, then native scripts in lexical order; a blocking result stops the adapter. Native `PermissionRequest` decisions and other structured responses pass back to Codex. Session-end and interrupt output is advisory and cannot keep a conversation running.

## The shipped hooks

Every shipped hook checks the `/dotagent` switch first (the `dotagent` row in the `state` table) and stays silent when it is `off`.

| Hook | Event | What it does |
|---|---|---|
| `rules_inject.sh` | prompt-submit | injects active `rules` rows into every prompt |
| `feedback_capture.sh` | prompt-submit | stamps the turn marker, and when the prompt matches the correction pattern injects an instruction to restate the request and save the lesson to `memories` |
| `commit_style_check.sh` | pre-tool | denies `git commit` when the message breaks universal rules (AI attribution trailers, overlong summary, trailing period), injects the style otherwise |
| `pr_style_reminder.sh` | pre-tool | injects PR body style right when `gh pr create` or a body PATCH is about to run |
| `code_style_reminder.sh` | pre-tool | injects per-file-type writing style (test style for test files, source style for app code) at write time |
| `style_check.sh` | post-tool | greps only the lines the change ADDED (via `git diff`) for the banned patterns in its instructions json and feeds findings back, legacy code never trips it |
| `memory_save_check.sh` | stop | blocks ending a turn that edited files without writing anything to `memory.db`, forcing the save (or an explicit "nothing to save") |
| `session_restore.sh` | session-start | injects the full memory snapshot (rules, memories catalog, diary, last session, tasks, bugs, decisions, learnings) for the checkout branch at session open, making RESTORE deterministic |

The valuable trick in `style_check.sh`: it diffs the file against HEAD and checks only added lines, so project style rules apply to new code without forcing a cleanup of everything the file already contained.
