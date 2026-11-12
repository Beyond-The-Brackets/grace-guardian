---
description: Run Grace's first check on this project, on this machine — a score and the 3 most serious problems, nothing uploaded
disable-model-invocation: true
---

Run Grace's quick check on this project, on my machine.

1. Say in one line starting `🧠 Grace — Check` that the check runs here, with no upload, and takes under a minute.
2. Run `npx -y @agent-grace/cli check` from the repository root (`git rev-parse --show-toplevel`, or the current folder if it is not a git repository). Let its progress show.
3. Give me what it printed: the score, and the problems in the order it lists them — at most 3. Keep its words. Do not add problems of your own, and do not call anything critical that it did not.
4. Call `grace_first_check` with the current working directory, the score and how many problems it reported. Numbers only: never code, paths or problem text.
5. Offer, in one sentence, the next step it suggests. If Grace is not set up for this repository yet, that is `/grace-guardian:grace-setup`.
