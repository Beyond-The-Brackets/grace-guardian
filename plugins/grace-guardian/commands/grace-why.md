---
description: Why is this line here? Who or what wrote it, for what, what was checked, who approved it, and what the team knows of the file
argument-hint: "<path>[:<line>]"
disable-model-invocation: true
---

Tell me why this code is here: $ARGUMENTS

1. Split what I gave into a file path and, if there is one, a line number (`src/pay.ts:42` → `src/pay.ts`, line 42). If I gave no line, use the file's last commit.
2. From the repository root, find the commit:
   - with a line: `git blame -L <line>,<line> --porcelain -- <path>`, the first word of the first line;
   - without a line: `git log -1 --format=%H -- <path>`.
   If the commit is all zeros, the line is not committed yet: say so and stop.
3. Call `grace_why` with `path`, `line`, `sha` and `cwd` set to the repository root (`git rev-parse --show-toplevel`). Send nothing else: no code.

Give me Grace's answer as it is. Do not add a reason, an author or an approval Grace did not give.
