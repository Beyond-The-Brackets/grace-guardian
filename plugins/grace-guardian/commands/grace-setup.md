---
description: Choose what Grace may see in this repository — nothing leaves your machine beyond paths and fingerprints until you choose
argument-hint: "[off | metadata | full — optional, to skip the question]"
disable-model-invocation: true
---

I want to set Grace up for this repository and choose what it may see. $ARGUMENTS

This is my request, so these steps are mine. Do them in order, and stop to ask me where it says so.

1. Call `grace_privacy` with the current working directory. If it says the folder is not connected to Grace, connect it first: `grace_connect_repo` when `git remote get-url origin` shows a GitHub repository, `grace_connect_local` otherwise. Then call `grace_privacy` again.
2. Show me, in plain words and in this order:
   - what each choice sends: **off**, **metadata** (the default, no file content), **full** (needed for the secret check on written code and for proven fixes);
   - what is never read, and what Grace keeps and for how long, as `grace_privacy` says it;
   - the link to "What Grace sees" it gives.
   Do not add claims of your own about privacy.
3. Ask me which of the three I want, unless I already said it above. Then ask whether there are folders Grace must never read (for example `legal/` or `secrets/`). Wait for my answers.
4. Call `grace_privacy_choose` with my choice and those folders. If it refuses because I am not an owner or admin, tell me who can do it and stop here.
5. Only if I chose **full**: show me the hooks it returned and ask before you write them into this project's `.claude/settings.json`. Keep every hook already there. If I say no, my choice still stands, but tell me the text of edits will not reach Grace until those hooks are installed.
6. Tell me in one line starting `🧠 Grace — Setup` what was recorded.
7. Unless I chose **off**, ask me: "See Grace step in? It takes 30 seconds, it is a demonstration, and nothing gets written." If I say yes:
   - say in one line that this is Grace's exercise, not a real problem;
   - create the file `.grace/exercise/risky-change.ts` with the single line `export const DEMO = "grace exercise";` — Grace refuses this path on purpose;
   - show me Grace's refusal and its reason as Grace wrote it, and confirm nothing was written;
   - if the file WAS written, the guardian's hooks are not running in this session: delete the file, and tell me `/mcp` must show `plugin:grace-guardian:grace` connected.
8. Ask me: "Run the first check now?" If I say yes, do what `/grace-guardian:grace-check` describes.
