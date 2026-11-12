---
description: Show the evidence Grace holds for your recent commits — risk, what was checked, tests, and whether Grace verified them
argument-hint: "[commit sha]"
disable-model-invocation: true
---

Show me the evidence Grace holds for my commits.

Call `grace_evidence` with `cwd` set to this repository's root folder (`git rev-parse --show-toplevel`). If I gave a commit after the command ($ARGUMENTS), pass it as `sha`; otherwise pass this session's id as `session` if you know it, and if that returns nothing, call it again without `session` for the latest commits.

Give me its answer as it is: the status, the risk and its reasons, what was checked, the tests, the files and the link. Do not add a verdict, a risk or test results of your own.
