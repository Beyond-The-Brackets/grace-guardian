# Grace Guardian — a Claude Code plugin

Grace Guardian watches the code your AI agent writes. Installed as a plugin, Grace stops being a
tool your assistant *may* call and becomes one that speaks up on its own:

| Moment | What Grace does |
| --- | --- |
| Session starts | Tells the assistant how the project stands, the areas that break, the debt that is deliberate — and the rule below. |
| You send a prompt | Adds what the team already decided about the subject, including approaches tried and rejected. On a deploy request: the production verdict, in plain language. On a request that touches a data model, auth or an API: what this project knows that makes the senior's questions concrete. Pushes back on the request itself ("make the tests pass", "delete this") only when this project gives it a reason to — open findings on its tests, deliberate debt, a dependency map it holds. |
| You leave plan mode | Reads the plan against the project: names the files it touches that the team has already ruled on, the open issues in those files, the dependency map it did not consult — and puts it back to you when it crosses settled ground in silence. |
| Before a file is written | Refuses a credential about to land in code. Asks before an edit in a sensitive area, a lockfile, an env file. Recalls what the project remembers about that file and its open issues. Raises the situation the write opens (a model, a route, an auth check) once per area, when the project has history on it. |
| Before a shell command | Refuses `git commit` / `git push` while changed files have not been reviewed. Asks before anything hard to undo (`push --force`, `rm -rf`, `prisma migrate reset`, `curl … \| sh`). |
| After a file is written | Names a second copy of a helper already written elsewhere in this session. Points at a swallowed error, a muted test or a silenced checker only in a file this project already has history on. Notes the file as changed and not yet reviewed. |
| Before the assistant finishes | Asks once for a review of what changed: Grace hands a brief, your assistant reviews with its own model, Grace scores what is new. |

## What you see in the conversation

When Grace has something to say on a prompt, an edit or a command, Claude Code shows you one line
starting `🧠 Grace —` with the start of what Grace noted. That line goes to you, not to the model:
it is the plugin's way of showing Grace at work, and it never approves or changes a tool call. A
check with nothing to add shows nothing. At the start of a session you get one line saying whether
the guardian is on; at the end, one line if writes happened that no check ever answered.

The plugin also adds one command you type yourself: `/grace-guardian:grace-audit` runs a full audit
the way Grace's work order describes it — one subagent for each of the 15 dimensions, each given your
team's auditor profile — and reports which dimensions were and were not covered.

## When Grace speaks — and when it does not

Grace runs next to a model that has the file open. Anything that model can deduce alone from the
file — "a migration needs a down path", "an empty `catch` swallows the error" — is noise when Grace
says it, and noise teaches people to skip the block. So the guardian has one rule: **it speaks only
when it knows something about THIS project that the assistant cannot see in the file** — a decision
the team made, an incident, an open finding, what depends on what, how the last audit read it.

Silence therefore means "nothing project-specific to add", never "approved". The two things Grace
still refuses regardless — a secret in code, an unreviewed commit — are gates, not advice.

The guardian never approves a tool call or changes its input. When it has nothing against an edit
or a command, it makes no decision and Claude Code's normal permission flow decides; it can only
refuse a call or ask you.

Four situations get a full playbook (a data model created or changed · auth or permissions touched ·
an endpoint added · getting ready for production). Your assistant can ask for them explicitly with
`grace_check_situation`, get the production verdict with `grace_ready_for_prod`, and get an
orchestration plan for a feature — the roles to run as subagents, their rules, this project's
context — with `grace_plan_feature`. All deterministic, no Grace credits.

Grace never writes code and never spends Grace credits from the editor. Everything above is
deterministic — no model call, no credit. The review at the end is done by **your** assistant's
model, framed and scored by Grace.

## Install

Ask Claude Code to do it — this is the whole setup, and it needs no `claude` command on your PATH:

> Set up Grace on this project. Open `~/.claude/settings.json` (create it as `{}` if it is not
> there), parse it, keep everything already in it, and merge in these two entries, then write it
> back — do not replace the file:
>
> ```json
> {
>   "extraKnownMarketplaces": {
>     "grace": { "source": { "source": "github", "repo": "Beyond-The-Brackets/grace-guardian" } }
>   },
>   "enabledPlugins": { "grace-guardian@grace": true }
> }
> ```

Or type it yourself, in Claude Code:

```
/plugin marketplace add Beyond-The-Brackets/grace-guardian
/plugin install grace-guardian@grace
```

Either way: quit and reopen Claude Code, then `/mcp` → **grace** → sign in with your Grace account
when the browser opens. That is all — no key, no binary, no npm, and nothing else to connect: the
plugin carries its own connection to Grace.

Try it locally from this repository instead:

```
claude --plugin-dir ./plugin/grace-guardian
```

## Self-hosted Grace

Point the plugin at your own instance by setting `GRACE_API_URL` (for example
`https://grace.corp.example`, no trailing slash) in the environment Claude Code starts from. The
plugin's MCP connection (`.mcp.json`, `${GRACE_API_URL:-https://api.agent-grace.com}/mcp/guardian`), every
`mcp_tool` hook that rides on it, and the shell hooks (`canary.sh`, `require-guard.sh`,
`commit-guard.sh`, `verify-guard.sh`) all read the same variable, so nothing keeps calling the SaaS.
Unset, it is `https://api.agent-grace.com`. Check it once: `/mcp` should list **grace** at your URL.

If `/mcp` still shows `https://api.agent-grace.com`, your Claude Code version does not expand
variables in a plugin's `.mcp.json`. Do not work around it with a second `grace` server — the hooks
are bound to the plugin's own (`plugin:grace-guardian:grace`). Copy the plugin directory, write your
URL in its `.mcp.json`, and load the copy with `claude --plugin-dir`. The shell hooks follow
`GRACE_API_URL` either way.

## What leaves your machine

The plugin on its own sends Grace **file paths, hashes and sizes** — never the text of an edit, a
prompt or a plan. Its shell hooks identify the session with a one-way digest of Claude Code's
session id, never the id itself, and the folder with a digest of its path. Nothing else is sent until someone chooses, per repository, in the app
(`What Grace may read`) or when your assistant runs the setup:

| Choice | What is sent | What Grace can still do |
| --- | --- | --- |
| **off** | nothing | nothing — the guardian is switched off |
| **metadata** *(what runs until a choice is made)* | paths, hashes, sizes | track what changed, hold an unreviewed commit, compare reviews to its own copy of the repository |
| **full** | also the text of each edit, the prompt and the plan | also the secret check on written code, early remarks on what was just written, plan and prompt challenges |

`full` adds a second set of hooks (the ones that carry text) to your Claude Code settings; the setup
hands them over. Every receipt is listed in the app, with the file and the size — never the text.
The shell command a `git`/`rm`-type gate has to read is the one exception: it is sent in every mode.

## Strictness

The guardian's strictness is a team setting, on your Grace account (`app.agent-grace.com/editor`):

- **advise** — Grace only adds context. It never blocks, never asks.
- **guard** (default) — refuses a certain secret and an unreviewed commit; asks before a sensitive
  area, an env file, a generated file; advises elsewhere.
- **strict** — also refuses edits in sensitive areas until the assistant has recalled what the
  project remembers, and refuses destructive commands outright.

Under `--dangerously-skip-permissions`, nobody can answer an "ask": Grace says so in context, and
`strict` turns those into refusals.

## When the folder is not recognised

Grace's server cannot see your git remote. It binds a folder to an app by name (folder or parent
folder vs repository name) or because the account has a single app. When it cannot tell, it says so
at session start and does **not** challenge edits; ask your assistant to call `grace_guard_bind`
with the folder path and the app id, once.

## If Grace goes quiet

Hooks cannot renew an expired connection. A small canary runs at session start: if Grace is
reachable but the guardian says nothing before your first edit, run `/mcp` and reconnect **grace**.
The `/editor` page in Grace shows when the guardian last spoke for each member of the team.

## Disable

`/plugin uninstall grace-guardian`, or set `"disableAllHooks": true` in `.claude/settings.local.json`
for one repository.
