---
name: four-agent-ship
description: Run a requested code change through separate planning, implementation, testing, and final-review subagents. Use when the user asks to ship a feature, use the four-agent workflow, or explicitly invokes $four-agent-ship. Do not use for small explanations or one-line edits unless the user requests the full workflow.
---

# Four-Agent Ship

Use four clearly separated stages. Run them sequentially because each stage depends on the previous result.

## Before starting

- Restate the requested outcome and important boundaries in one short update.
- Inspect the current project status and preserve unrelated user changes.
- If this is a Git repository on `main` or `master`, stop before editing and ask the user to choose or create a feature branch. Do not create a branch without authorization.
- If the folder is not a Git repository, say that no branch rollback is available, then continue because explicit invocation of this skill authorizes the workflow itself.
- Never commit, push, merge, open a pull request, deploy, publish, or upload externally unless the user separately requests it.

## Stage 1: Planner

Create the `planner` subagent in read-only mode. Give it the user's request, relevant constraints, and project location. Ask it to inspect the real code paths and return:

- exact files and symbols involved;
- intended behavior and acceptance criteria;
- edge cases and meaningful verification;
- unanswered questions that would materially change the implementation.

Wait for the planner. If material questions remain, stop and ask the user. Otherwise, briefly check that the plan stays inside the request before continuing.

## Stage 2: Coder

Create the `coder` subagent and provide the approved plan. The coder owns production-code edits for this run. Tell it to preserve unrelated changes, follow existing project conventions, and report every changed file plus any limitation.

Wait for completion. Inspect the resulting diff before starting tests. If the implementation clearly exceeds the approved scope, stop and report it.

## Stage 3: Tester

Create the `tester` subagent with the request, approved plan, coder summary, and current diff. It may create or update test files and run checks, but it must not repair production code. Require it to report:

- commands/checks run;
- passed and failed results;
- whether acceptance criteria are covered;
- gaps that still require physical-device, account, network, or user testing.

If a required test or build fails, stop the pipeline and return the failure. Do not silently send the work back to the coder in a loop.

## Stage 4: Reviewer

Create the `reviewer` subagent in read-only mode. Give it the original request, plan, coder summary, test report, and current diff. It must prioritize correctness, safety, regressions, missing requirements, and meaningful test gaps. It returns exactly one verdict:

- `APPROVE`: ready for the user to inspect;
- `CHANGES NEEDED`: specific fixable problems remain;
- `BLOCK`: a serious correctness, security, or data-loss risk remains.

The reviewer never edits files.

## Final response

Wait for all four stages that were reached. Report the reviewer verdict first, then summarize changed files, verification, and anything that remains unverified. Clearly distinguish code checks from physical-device or live-service testing. Leave the working tree for the user to inspect.
