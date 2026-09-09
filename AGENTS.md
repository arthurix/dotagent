# Agent Memory System

You are a developer agent with persistent SQLite memory.
Database: `.agent/memory.db`
Schema: `.agent/init-db.sql`

This file documents **how the agent remembers**: the RESTORE → REPORT → WORK → SAVE cycle, the SQLite schema, and the memory commands.

- **Coding conventions, identity, forbidden actions, response format** → `.agent/rules/` (ships empty, add your project's rule files, every file there is loaded each session)
- **Auto-loaded** via each platform's context file, all pointing at this one file: Codex reads `AGENTS.md` natively, Claude Code reads it through the `CLAUDE.md` symlink, Gemini CLI via `"contextFileName": "AGENTS.md"` in `.gemini/settings.json`. Claude Code and Codex can inject the RESTORE snapshot through the installed SessionStart hook; Codex hooks require trust review through `/hooks`. Without a snapshot, run RESTORE below.

---

## 1. The Cycle

This process is mandatory. Never skip any step.

```
RESTORE --> REPORT --> WORK --> SAVE --> REPEAT
```

One exception: when `sqlite3 .agent/memory.db "SELECT value FROM state WHERE key='dotagent'"` returns `off`, the whole cycle is disabled for this project. Work as a plain agent, no restore, no report, no saves, until it is turned back on. On Claude Code the session snapshot tells you this directly, on other tools check once at session start.

### RESTORE (every session start, before anything else)

**Step 1 — Load project rules.**

Read every file in your rules directory. If no rules directory exists, continue without rules.

**Step 2 — Load branch memory.**

When the installed SessionStart hook injects a snapshot (Claude Code or trusted Codex hooks), verify the branch matches the conversation and only re-run the queries for a different branch. If no snapshot was injected, run everything below yourself.

Run these commands. If any fail, bootstrap first (see section 4).

```bash
BRANCH=$(git branch --show-current)
sqlite3 .agent/memory.db "INSERT OR IGNORE INTO branches (name) VALUES ('$BRANCH')"
```

The `rules` rows loaded below are standing instructions, obey them for the whole session. Claude Code and trusted Codex hooks re-inject them on every prompt; without hooks this RESTORE load is the only delivery, so treat them as permanent.

**The checkout is only a default.** The user may run several chat windows against one working tree; each chat is one task on one feature branch. If the conversation names or implies a different branch than the checkout, use the conversation's branch as `BRANCH` for every load and save in this session. If it is unclear which task this chat belongs to, ask before restoring. Never carry another branch's tasks, bugs, hook findings, or context into this chat's report, answers, or next steps.

Then load context:

```bash
sqlite3 -header -column .agent/memory.db "SELECT name, content FROM rules WHERE active=1"
sqlite3 -header -column .agent/memory.db "SELECT type, count(*) AS count FROM memories GROUP BY type ORDER BY type"
sqlite3 -header -column .agent/memory.db "SELECT entry, workstream, created_at FROM diary ORDER BY id DESC LIMIT 2"
sqlite3 -header -column .agent/memory.db "SELECT summary, next_steps FROM sessions WHERE branch='$BRANCH' ORDER BY started_at DESC LIMIT 1"
sqlite3 -header -column .agent/memory.db "SELECT id, title, status FROM tasks WHERE branch='$BRANCH' AND status <> 'done' ORDER BY id"
sqlite3 -header -column .agent/memory.db "SELECT id, title, status FROM tasks WHERE branch='general' AND status <> 'done' ORDER BY id"
sqlite3 -header -column .agent/memory.db "SELECT id, title, status FROM bugs WHERE branch='$BRANCH' AND status = 'open'"
sqlite3 -header -column .agent/memory.db "SELECT id, title, status FROM refactorings WHERE branch='$BRANCH' AND status <> 'done' ORDER BY id"
sqlite3 -header -column .agent/memory.db "SELECT id, category, title FROM decisions WHERE branch='$BRANCH' AND status = 'active' ORDER BY created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT content FROM learnings WHERE (branch='$BRANCH' OR branch IS NULL) ORDER BY created_at DESC LIMIT 5"
```

### REPORT (MANDATORY — always print as your FIRST visible response)

**You MUST print this status report as the very first thing in every new conversation.** Do not skip it, even if the user's first message is a task request — print the report first, then address the task. Context files load invisibly; the user cannot see what you restored unless you print it.

Use this format:

```
-- Project rules loaded --
<list files from your platform's rules directory, or "none found">

-- Memory loaded from .agent/memory.db --
Long-term memories: <count per type, e.g. "24 feedback, 43 project, 6 reference"> — counts only, query the catalog and content on demand
Diary: <latest entry + its date, or "empty — ask what the user is working on only if the request is ambiguous">
Branch: <branch name>
Last session: <summary or "first session on this branch">
Pending tasks: <list titles + status, or "none">
General tasks (off-branch): <list titles + status, or "none">
Open bugs: <list titles, or "none">
Active refactorings: <list titles + status, or "none">
Recent decisions: <list category + title, or "none">
Recent learnings: <list content snippets, or "none">

-- Available agents (use @agent-name or ask to spawn one) --
<list agent names from .agent/agents/, or "none found">

-- Available workflows (say 'load <name>' to activate) --
<list workflow names from .agent/workflows/, or "none found">

-- Quick tips (type these in chat) --
- Re-print this report any time: "print the session report"
- Show or search branch memory on demand: "show memory"   "search memory for payments"
- Search prior memory (bugs, learnings, decisions, sessions):
    "what do we know about invoice numbering?"
    "did we fix this before?"
    "show open bugs on this branch"
- Turn the memory system off or on for this project:
    "dotagent off"   "dotagent on"   (see the Dotagent Toggle section)
- Agents (.agent/agents/), workflows (.agent/workflows/) and skills (.agent/skills/) are extension points: drop in your own md files and they are picked up automatically. Skills activate when the task matches, agents are called with @name, workflows with "load <name>".
- Rules (in .agent/rules/) are loaded automatically every session — to change how the AI codes, add or edit md files there.
- Open tasks and bugs above carry over between sessions automatically.
```

### MEMORY SEARCH (for every new request)

Before planning, answering a substantive question, or implementing anything, check whether the request matches prior memory.

This is mandatory when the user asks about:
- Something already solved before
- Insights, findings, learnings, prior decisions, prior bugs, or previous sessions
- Existing patterns, conventions, or known gotchas
- "How did we do this before?" / "Did we already fix this?" / "What do we know about X?"

There is no separate `insights` or `findings` table. Search these tables instead:
- `memories` for durable cross-session knowledge: user preferences, standing feedback, project facts, server/tool references
- `learnings` for insights, findings, gotchas, conventions
- `bugs` for issues found or fixed before
- `tasks` for work completed in the past
- `sessions` for prior summaries and next steps
- `decisions` for architecture or design choices
- `refactorings` for restructuring work
- `state` for small key-value facts

Use 1-3 concrete search terms from the user's request. Query narrowly and summarize the relevant hits before proceeding.

Search order:
1. `memories`
2. `learnings`
3. `bugs`
4. `tasks`
5. `decisions`
6. `sessions`
7. `refactorings`
8. `state`

Prefer current-branch matches, but search across all branches when looking for prior solutions or reusable knowledge.

Example targeted queries:

```bash
sqlite3 -header -column .agent/memory.db "SELECT name, type, description FROM memories WHERE name LIKE '%TERM%' OR description LIKE '%TERM%' OR content LIKE '%TERM%' LIMIT 5"
sqlite3 .agent/memory.db "SELECT content FROM memories WHERE name='EXACT_NAME'"
sqlite3 -header -column .agent/memory.db "SELECT id, category, content, branch, created_at FROM learnings WHERE content LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT id, title, status, fix_description, branch, fixed_at FROM bugs WHERE title LIKE '%TERM%' OR description LIKE '%TERM%' OR fix_description LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, fixed_at DESC, created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT id, title, status, result, branch, completed_at FROM tasks WHERE title LIKE '%TERM%' OR description LIKE '%TERM%' OR result LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, completed_at DESC, created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT id, category, title, decision, branch, created_at FROM decisions WHERE title LIKE '%TERM%' OR context LIKE '%TERM%' OR decision LIKE '%TERM%' OR alternatives LIKE '%TERM%' OR consequences LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT id, summary, next_steps, branch, started_at FROM sessions WHERE summary LIKE '%TERM%' OR next_steps LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, started_at DESC LIMIT 5"
```

If the first search term is too broad or returns nothing useful, refine it and search again. Do not claim "nothing in memory" until you have tried a reasonable targeted lookup.

### WORK

Execute the requested task. Follow the rules loaded from your rules directory.

Before new implementation, first report any relevant prior memory you found:
- similar bugs previously fixed
- related tasks already completed
- learnings or decisions that constrain the solution
- prior sessions that describe the same area

If relevant prior memory exists, reuse it. Do not rediscover solved work from scratch.

**Test discipline (mandatory after every code change):**

After writing or modifying code, run the existing test suite. Then apply this rule:

- **Tests fail** → expected. Fix the code until they pass.
- **Tests pass** → the changed code is not covered. Do not move on. Write tests that cover the new or changed behavior first, then verify they pass.

The invariant is: *any meaningful code change must cause at least one test to fail before the fix lands.* If no test fails, the code is untested — treat this as a bug in the test suite, not a green light.

**Post-task quality checklist (mandatory before declaring done):**

After implementation, run these checks in order:

1. **Scope check** — `git diff --stat` to count changed lines. If a simple task changed more than ~50 lines or touched more than 3 files, you probably changed too much. Revert what wasn't asked for.
2. **Lint changed files only** — run the project's linter on the files you touched, nothing project-wide.
3. **Run tests** — run the project's test command for the relevant files. Fix any failures you introduced.
4. **Dependency audit** (if dependencies changed) — run the ecosystem's audit tool (`npm audit`, `bundle audit`, `pip-audit`, ...). Fix any critical/high vulnerabilities before proceeding.
5. **Theme check** (frontend only) — if the app has light and dark themes and you changed styling, verify both.
6. **Review your own diff** — Read through `git diff` as if you were a reviewer. Would you approve this PR? Does every changed line relate to the original request?

If any check fails, fix it before reporting completion.

### SAVE

Update memory at these moments:
- After completing a task
- After finding or fixing a bug
- After making an architecture or design decision
- After starting or completing a refactoring
- When learning something important
- Before the session ends
- When switching branches

**Always announce saves to the user.** Before writing to the database, tell the user what you are saving and to which table. Use this format:

```
-- Saving to memory --
table: <table name>
what: <one-line description of what is being saved>
```

### How to classify what happened

During work, identify what to save by asking these questions:

**Is it a task?** -- The user asked you to do something (add a feature, change behavior, update a component, write tests). Break multi-step work into individual tasks. Each task gets a row in `tasks`.

**Is it a bug?** -- You found something broken: wrong behavior, crash, missing validation, broken UI, incorrect data. Log it in `bugs` even if you fix it immediately -- the record matters for future context.

**Is it a decision?** -- You chose between multiple valid approaches (e.g., Context vs Redux, card layout vs list, REST vs GraphQL, which component to reuse). Log it in `decisions` with the alternatives you rejected and why. Categories: `architecture`, `ui-design`, `api`, `data`, `security`, `performance`.

**Is it a refactoring?** -- You restructured code without changing behavior: extracting a component, renaming, splitting a file, reorganizing modules. Log it in `refactorings` with the scope (which files/components).

**Is it a learning?** -- You discovered something non-obvious about the codebase: an undocumented pattern, a gotcha, a performance constraint, a convention that isn't written down. Log it in `learnings`. Use `branch IS NULL` if it applies to the whole project.

**Is it a diary entry?** -- The user states what they are working on, their priorities, a blocker, or outside context (a meeting outcome, a deadline, which work stream this chat belongs to). Insert into `diary` verbatim-ish, one row per statement. Diary is the user's voice only: never write agent work into it, that already lands in `sessions` and `tasks`. To answer "what was I working on lately", combine the last diary entries with recent `sessions` across all branches.

**Is it a durable memory?** -- Knowledge that outlives any branch and shapes how future sessions behave: who the user is, standing feedback on how to work, project constraints not derivable from code, server or tool references. Upsert into `memories` (name = short-kebab-slug, type = user | feedback | project | reference, description = one line for the catalog, content = the fact plus why and how to apply). Update the existing row when the topic already exists; never create near-duplicates.

**Is it off-branch?** -- The request has nothing to do with the current branch: a general question, tooling, infra, a side task. Route it by kind, never onto the branch you happen to be on. Knowledge goes to `memories` (durable) or `learnings` with branch NULL (global). User context goes to `diary`. Actual work items -- tasks, bugs, and the session rows describing that work -- go to the reserved branch `general`, which the schema seeds so it always exists.

**Always save a session** -- Before the conversation ends, summarize what was done and what comes next. This is the most important save -- it's what the next session reads first.

---

## 2. Save Commands

**Rules for every sqlite3 call:**
- Use the **literal branch name** obtained during RESTORE (e.g. `'main'`|`'master'`). Never prefix with `BRANCH=$(git branch --show-current) &&` — that breaks auto-approval and is unnecessary.
- Each sqlite3 call must be its **own Bash tool call**. Never chain multiple with `&&`.
- Inside a double-quoted bash string, single quotes are **literal** — write `datetime('now')`, never `datetime(''now'')`. If a field value contains single quotes, strip or replace them with spaces.

### Task management

```bash
# Create task
sqlite3 .agent/memory.db "INSERT INTO tasks (branch, title, description) VALUES ('BRANCH', 'TITLE', 'DESCRIPTION')"

# Start task
sqlite3 .agent/memory.db "UPDATE tasks SET status='in_progress' WHERE id=ID"

# Complete task
sqlite3 .agent/memory.db "UPDATE tasks SET status='done', result='WHAT_WAS_DONE', completed_at=datetime('now') WHERE id=ID"

# Block task
sqlite3 .agent/memory.db "UPDATE tasks SET status='blocked', result='WHY_BLOCKED' WHERE id=ID"
```

### Bug tracking

```bash
# Log bug
sqlite3 .agent/memory.db "INSERT INTO bugs (branch, title, description, file_path) VALUES ('BRANCH', 'TITLE', 'DESCRIPTION', 'FILE_PATH')"

# Fix bug
sqlite3 .agent/memory.db "UPDATE bugs SET status='fixed', fix_description='HOW_FIXED', fixed_at=datetime('now') WHERE id=ID"
```

### Decisions

```bash
# Log decision
sqlite3 .agent/memory.db "INSERT INTO decisions (branch, category, title, context, decision, alternatives, consequences) VALUES ('BRANCH', 'CATEGORY', 'TITLE', 'CONTEXT', 'DECISION', 'ALTERNATIVES', 'CONSEQUENCES')"
# Categories: architecture, ui-design, api, data, security, performance

# Supersede decision
sqlite3 .agent/memory.db "UPDATE decisions SET status='superseded' WHERE id=ID"
```

### Refactorings

```bash
# Plan refactoring
sqlite3 .agent/memory.db "INSERT INTO refactorings (branch, title, reason, scope) VALUES ('BRANCH', 'TITLE', 'REASON', 'FILES_OR_COMPONENTS')"

# Start refactoring
sqlite3 .agent/memory.db "UPDATE refactorings SET status='in_progress' WHERE id=ID"

# Complete refactoring
sqlite3 .agent/memory.db "UPDATE refactorings SET status='done', result='WHAT_CHANGED', completed_at=datetime('now') WHERE id=ID"

# Defer refactoring
sqlite3 .agent/memory.db "UPDATE refactorings SET status='deferred', result='WHY_DEFERRED' WHERE id=ID"
```

### Learnings

```bash
# Save learning
sqlite3 .agent/memory.db "INSERT INTO learnings (category, content, branch) VALUES ('CATEGORY', 'WHAT_WAS_LEARNED', 'BRANCH_OR_NULL')"
# Categories: pattern, gotcha, decision, architecture, performance
# Use NULL for branch if the learning is global (applies to all branches)
```

### Diary (the user's worklog, their voice only)

```bash
# Save what the user says they are working on / blocked on
# workstream = stable feature slug (e.g. 'billing-revamp'), shared across all branches and PRs of that feature; NULL only for cross-project context
sqlite3 .agent/memory.db "INSERT INTO diary (entry, workstream) VALUES ('ENTRY', 'WORKSTREAM')"

# What was the user working on lately (diary = intent, sessions = what agents did)
sqlite3 -header -column .agent/memory.db "SELECT entry, workstream, created_at FROM diary ORDER BY id DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT branch, summary, started_at FROM sessions ORDER BY started_at DESC LIMIT 5"
```

### Long-term memories

```bash
# Upsert a durable memory (types: user, feedback, project, reference)
sqlite3 .agent/memory.db "INSERT INTO memories (name, type, description, content) VALUES ('SLUG', 'TYPE', 'ONE_LINE_DESCRIPTION', 'CONTENT') ON CONFLICT(name) DO UPDATE SET type=excluded.type, description=excluded.description, content=excluded.content, updated_at=datetime('now')"

# Read one memory in full
sqlite3 .agent/memory.db "SELECT content FROM memories WHERE name='SLUG'"

# Delete a memory that turned out wrong
sqlite3 .agent/memory.db "DELETE FROM memories WHERE name='SLUG'"
```

### Session save

```bash
# Save session summary (do this before session ends)
sqlite3 .agent/memory.db "INSERT INTO sessions (branch, summary, next_steps, model) VALUES ('BRANCH', 'WHAT_WE_DID', 'WHAT_TO_DO_NEXT', 'MODEL_NAME')"
```

### Branch switch

```bash
# Save current branch state
sqlite3 .agent/memory.db "INSERT INTO sessions (branch, summary, next_steps) VALUES ('OLD_BRANCH', 'SUMMARY', 'NEXT_STEPS')"
sqlite3 .agent/memory.db "UPDATE branches SET status='paused', updated_at=datetime('now') WHERE name='OLD_BRANCH'"

# Activate new branch
sqlite3 .agent/memory.db "INSERT OR IGNORE INTO branches (name) VALUES ('NEW_BRANCH')"
sqlite3 .agent/memory.db "UPDATE branches SET status='active', updated_at=datetime('now') WHERE name='NEW_BRANCH'"

# Then run RESTORE for the new branch
```

---

## 3. Branch Awareness

- Always detect current branch with `git branch --show-current`
- The memory branch is the conversation's task branch, not necessarily the git checkout — multiple chat windows share one working tree; when they differ, the conversation wins
- Compare with the last known branch in the database
- If the branch changed since the last session: save old branch context, then load new branch context
- Each branch has its own tasks, bugs, sessions, decisions, and refactorings
- Learnings with `branch IS NULL` are global and always loaded

---

## 4. Self-Bootstrap

If `.agent/memory.db` does not exist, create it:

```bash
sqlite3 .agent/memory.db < .agent/init-db.sql
```

If `.agent/init-db.sql` does not exist, report the error and ask the user to run the install script.

If a branch is not in the database, register it:

```bash
sqlite3 .agent/memory.db "INSERT OR IGNORE INTO branches (name) VALUES ('BRANCH_NAME')"
```

---

## 5. Skills

Skills are project-specific instructions stored in `.agent/skills/`. No platform symlink is wired; an agent loads a skill by reading its file when the task matches the description in its SKILL.md.

### Rules (auto-loaded)

Rule files are auto-loaded on every session start via your platform's rules directory (see Step 1).
Read all files in that directory and follow their instructions.

These define project identity: tech stack, coding conventions, component library, etc.

### Workflows (on-demand)

Workflow files are loaded when the user says "load <name>".
The name is the filename without the `.md` extension.

To load a workflow:
1. Read the workflow file from `.agent/workflows/<name>.md`
2. Follow its instructions for the current task
3. When the workflow completes, save results to the appropriate database table

On startup, list available workflows so the user knows what is available.

---

## 6. Context Budget

Keep restore queries small to save tokens:
- Sessions: `LIMIT 1` (only last session)
- Tasks: only `status <> 'done'`
- Bugs: only `status = 'open'`
- Decisions: `LIMIT 5` (most recent active)
- Learnings: `LIMIT 5` (most recent)
- Refactorings: only `status <> 'done'`

Do not dump the entire database into context. Query only what is needed for the current branch.

However, the small restore snapshot is not enough for repeated or historical questions. For each new request, run a targeted memory search when prior work might exist. Keep those searches narrow: a few specific terms, relevant tables only, and `LIMIT 5`.

---

## 7. Quick Reference

### Dotagent Toggle

Turn the memory system on or off for this project, or show its state. Works in any tool: the user says "dotagent on", "dotagent off", or "dotagent status". On Claude Code /dotagent is an alias for this section.

```bash
# on — then run RESTORE and print the REPORT
sqlite3 .agent/memory.db "INSERT OR REPLACE INTO state (key, value, updated_at) VALUES ('dotagent', 'on', datetime('now'))"

# off — from this point skip the memory cycle entirely, no restore, no report, no saves. On Claude Code the hooks silence themselves by reading this row. Confirm in one line.
sqlite3 .agent/memory.db "INSERT OR REPLACE INTO state (key, value, updated_at) VALUES ('dotagent', 'off', datetime('now'))"

# status — report the value in one line
sqlite3 .agent/memory.db "SELECT COALESCE((SELECT value FROM state WHERE key='dotagent'), 'on')"
```

### State key-value store

For quick state that does not fit other tables:

```bash
sqlite3 .agent/memory.db "INSERT OR REPLACE INTO state (key, value, updated_at) VALUES ('KEY', 'VALUE', datetime('now'))"
sqlite3 .agent/memory.db "SELECT value FROM state WHERE key='KEY'"
```

### Search prior memory by topic

Replace `TERM` with a concrete keyword from the user's request.

```bash
BRANCH=$(git branch --show-current)
sqlite3 -header -column .agent/memory.db "SELECT id, category, content, branch, created_at FROM learnings WHERE content LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT id, title, status, fix_description, branch, fixed_at FROM bugs WHERE title LIKE '%TERM%' OR description LIKE '%TERM%' OR fix_description LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, fixed_at DESC, created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT id, title, status, result, branch, completed_at FROM tasks WHERE title LIKE '%TERM%' OR description LIKE '%TERM%' OR result LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, completed_at DESC, created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT id, category, title, decision, branch, created_at FROM decisions WHERE title LIKE '%TERM%' OR context LIKE '%TERM%' OR decision LIKE '%TERM%' OR alternatives LIKE '%TERM%' OR consequences LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT id, summary, next_steps, branch, started_at FROM sessions WHERE summary LIKE '%TERM%' OR next_steps LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, started_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT id, title, status, result, branch, completed_at FROM refactorings WHERE title LIKE '%TERM%' OR reason LIKE '%TERM%' OR scope LIKE '%TERM%' OR result LIKE '%TERM%' ORDER BY (branch='$BRANCH') DESC, completed_at DESC, created_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT key, value, updated_at FROM state WHERE key LIKE '%TERM%' OR value LIKE '%TERM%' ORDER BY updated_at DESC LIMIT 5"
```

### View all data for current branch

```bash
BRANCH=$(git branch --show-current)
sqlite3 -header -column .agent/memory.db "SELECT * FROM tasks WHERE branch='$BRANCH'"
sqlite3 -header -column .agent/memory.db "SELECT * FROM bugs WHERE branch='$BRANCH'"
sqlite3 -header -column .agent/memory.db "SELECT * FROM sessions WHERE branch='$BRANCH' ORDER BY started_at DESC LIMIT 5"
sqlite3 -header -column .agent/memory.db "SELECT * FROM decisions WHERE branch='$BRANCH'"
sqlite3 -header -column .agent/memory.db "SELECT * FROM refactorings WHERE branch='$BRANCH'"
sqlite3 -header -column .agent/memory.db "SELECT * FROM learnings WHERE branch='$BRANCH' OR branch IS NULL"
```

---

## 8. Rollback & Cleanup

Commands for deleting or rolling back incorrect/unwanted history.

### Delete specific records

```bash
# Delete task by ID
sqlite3 .agent/memory.db "DELETE FROM tasks WHERE id=ID"

# Delete bug by ID
sqlite3 .agent/memory.db "DELETE FROM bugs WHERE id=ID"

# Delete session by ID
sqlite3 .agent/memory.db "DELETE FROM sessions WHERE id=ID"

# Delete decision by ID
sqlite3 .agent/memory.db "DELETE FROM decisions WHERE id=ID"

# Delete refactoring by ID
sqlite3 .agent/memory.db "DELETE FROM refactorings WHERE id=ID"

# Delete learning by ID
sqlite3 .agent/memory.db "DELETE FROM learnings WHERE id=ID"
```

### Delete all history for a branch

**Use with caution** — this removes all memory for a branch.

```bash
# Delete all history for a branch
sqlite3 .agent/memory.db "DELETE FROM tasks WHERE branch='BRANCH'"
sqlite3 .agent/memory.db "DELETE FROM bugs WHERE branch='BRANCH'"
sqlite3 .agent/memory.db "DELETE FROM sessions WHERE branch='BRANCH'"
sqlite3 .agent/memory.db "DELETE FROM decisions WHERE branch='BRANCH'"
sqlite3 .agent/memory.db "DELETE FROM refactorings WHERE branch='BRANCH'"
sqlite3 .agent/memory.db "DELETE FROM learnings WHERE branch='BRANCH'"
```

### Rollback last session

```bash
# Undo the most recent session save
sqlite3 .agent/memory.db "DELETE FROM sessions WHERE id=(SELECT id FROM sessions WHERE branch='BRANCH' ORDER BY started_at DESC LIMIT 1)"
```

---

## 9. No Assumptions — EVER (Hard Rule)

**NEVER invent fallback values, default strings, placeholder data, or business logic that the user did not explicitly provide or approve.**

This includes but is not limited to:
- ❌ Adding fallback strings like `'Unknown'`, `'N/A'`, hardcoded emails, company names
- ❌ Deciding what happens when a value is `null` or empty without asking
- ❌ Choosing default behaviors for edge cases the user didn't mention
- ❌ Adding `|| 'fallback'` to any value without explicit instruction

**When you encounter ambiguity — STOP and ASK.** Present the options, recommend one, and wait. Do not silently pick one and ship it. Every assumed value is a bug the user didn't ask for and now has to find and review.

This is the reinforcement: **ask or don't write the code.**

---

## 10. Where Coding Rules Live (Not Here)

This file does **not** contain coding rules, identity, forbidden actions, or response format. Those live in `.agent/rules/`, which ships empty and is yours: every md file you put there is auto-loaded at session start. Typical split: a `general.md` with identity and discipline, plus one file per stack layer with its conventions.

If you want to change coding behavior, add or edit files in `rules/`. If you want to change how memory works, edit this file.
