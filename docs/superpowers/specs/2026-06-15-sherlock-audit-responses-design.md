# Sherlock Audit Responses Design

## Goal

Create one Chinese response document for every unanswered Sherlock PR review
thread and every Sherlock Issue in
`sherlock-audit/2026-05-enhanced-may-26th-2026`.

The analysis must decide whether each reported condition is reachable through
the complete deployed-contract workflow. A suspicious local code fragment is
not sufficient evidence if all real external entry points, authorization
checks, signatures, state transitions, or asset invariants prevent the
condition.

## Scope

- Include the 50 root PR review threads returned by the GitHub review-comment
  API, except the 5 threads containing a reply from `6xiaowu9`.
- Include Issues #38, #39, and #40.
- Do not create separate documents for replies inside a review thread.
- Use replies by auditors as supporting context.
- Exclude PR descriptions, commit messages, and review records without a root
  line comment.

The expected output is 48 response documents: 45 PR comments and 3 Issues.

## Source Of Truth

- Audit source revision:
  `Enhanced-Finance/contracts@4e55bcfa33a0ebca729f81cb4f2af4eaaf548365`.
- Response target revision: the current `fix/audit` working tree.
- Original problem text and links: GitHub API data from the private Sherlock
  repository.
- Runtime behavior: Solidity source, inherited contracts, interfaces, scripts,
  tests, and deployment/configuration paths in this repository.

Each response distinguishes behavior at the audited revision from behavior
already changed on `fix/audit`.

## Reachability Analysis

For every item, trace and document:

1. The public or external entry point that can initiate the reported flow.
2. The identity able to call it, including owner, manager, operator, trusted
   taker, signer, vault owner, or unrestricted user checks.
3. Signature contents, replay protection, payload constraints, and caller-to-
   payload relationships.
4. Required protocol phase, pause state, expiry window, whitelist state, vault
   type, collateral type, and prior state transitions.
5. The internal call chain leading to the commented code.
6. Whether an attacker or affected user can construct all required state at the
   same time.
7. The resulting asset movement or persistent state corruption.
8. Existing mitigations and whether they fully prevent the claimed impact.

## Classification

Every answer uses one of these conclusions:

- `成立`: the complete call chain permits the claimed behavior and impact.
- `条件成立`: reachable only under explicit configuration or trust assumptions;
  the answer states whether those assumptions are supported.
- `不成立`: an earlier invariant or entry-point restriction prevents the
  reported scenario.
- `维护建议`: dead code, simplification, unused storage, documentation, or
  defense-in-depth without a demonstrated security impact.

The response also states whether the current `fix/audit` branch already fixes
or changes the result.

## Document Format

Files are stored under `docs/audit-responses/` with stable names:

- `pr-<number>-r<review-comment-id>-<slug>.md`
- `issue-<number>-<slug>.md`

Each file contains exactly these main sections:

```markdown
# [精炼后的问题标题](原始问题链接)

## 问题原文

<完整原文，保持审计者格式和代码块>

## 答复

**结论：成立 / 条件成立 / 不成立 / 维护建议**

<入口、约束、调用链、可达性、影响和当前分支状态>

## 修复建议

<成立且尚未修复：给 Codex 的可执行修复提示词>
<已修复：说明对应实现与测试，并给出复核提示词>
<不成立：明确写“无需修复”，可附建议补充的回归测试>
<维护建议：给出最小清理提示词，或说明保留原因>
```

The Codex prompt names concrete files, behavior, required regression tests, and
verification commands. It must not prescribe a code change before the
reachability conclusion is established.

## Index And Coverage

Create `docs/audit-responses/README.md` containing:

- source repository and analyzed revisions,
- exclusion rule and the 5 answered thread links,
- a table of all 48 included items,
- document link, source link, author, affected contract, classification, and
  current fix status,
- totals by classification.

Coverage verification compares the index source IDs with the GitHub API:

- every unanswered root review comment appears exactly once,
- every Issue appears exactly once,
- no answered thread appears as a response document,
- every document has all four required sections.

## Verification

- Re-fetch GitHub metadata and compare source IDs against generated filenames.
- Search for missing sections, placeholder text, broken relative links, and
  empty original bodies.
- Run targeted Forge tests when a conclusion depends on executable behavior.
- Run the full relevant test suite after all targeted checks.
- Manually review cross-contract findings, especially Controller,
  ControllerLogic, EnhancedOptions, Oracle, MarginCalculator, and
  EnhancedVault flows.
