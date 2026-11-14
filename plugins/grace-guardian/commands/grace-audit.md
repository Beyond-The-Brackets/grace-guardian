---
description: Audit this codebase with Grace's full method — one subagent per dimension, 15 of them, each given the team's auditor profile
argument-hint: "[app name or area to focus on — optional]"
disable-model-invocation: true
---

I am asking for a full Grace audit of this codebase. $ARGUMENTS

Run it the way Grace's work order describes it, here, on your own model. This is my request, so these steps are mine:

1. Call `grace_audit_brief` for this project. If Grace does not know this folder, `grace_connect_repo` (or `grace_connect_local` when there is no remote) comes first. If the work order is not ready, call `grace_audit_brief` again with the same `auditId`.
2. Tell me, in one line starting `🧠 Grace — Audit`, how many subagents you are about to launch and on which dimensions.
3. Build the system map the work order asks for, then launch **one subagent for each of Grace's 15 dimensions**. Not a split by area of the code, and not fewer subagents with several dimensions each. Give every subagent: the team's auditor profile exactly as the work order gives it, its own dimension exactly as listed, your system map, the family rules, and the leads already routed to its dimension.
4. Do the reading through those subagents. Do not read the repository yourself in their place.
5. Merge what comes back: the same cause reported by several dimensions is one finding. Send the result with `grace_audit_submit`, with `readPaths` (every file opened) and `dimensionsRead` (every dimension a subagent actually reviewed, clean ones included).
6. Tell me, in one line starting `🧠 Grace — Audit`, what Grace's reply says about coverage. If any dimension was not checked, say which, and run it before you call the audit done.

If a subagent fails or comes back empty, say so and re-launch that dimension. A dimension that was not run is "not checked", never "clean".
