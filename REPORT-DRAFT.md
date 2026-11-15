# DRAFT — Metric Immunefi Report: Ordered extension need not implement its hook — pool permanently bricks `removeLiquidity`

**Status: DRAFT — submission-ready, NOT submitted.**
**Reason not submitted:** Immunefi Novice submission fee (100 credits, ~100 USDC).
Fah's account holds ~0 USDC; waiting for the Immunefi Studio wave, same as
the two GMX drafts. Do NOT submit until the Studio "Ready" verdict, and do
NOT pay any fee from another source without Fah's explicit approval.

- **Program:** Metric — https://immunefi.com/bug-bounty/metric/information/
- **Severity: High** — maps exactly onto the listed Metric High impact
  **"Permanent freezing of funds"**.
- **Payout wallet:** `0x45859319d9a362f2146d0431dc30ab8f0ef1be73`
- **PoC repo:** https://github.com/Anyeps/metric-extension-hook-pool-brick-poc
- **Code under test:** `pool-contracts` @ `ddf8ae0`, `periphery-contracts` @
  `5ceaec3` (exact repo code, local deploy, no fork — see below).

---

# Part 1 — 7-Question Gate (run before writing the report)

## Q1: Can an attacker use this RIGHT NOW, step by step? — PASS

Yes, and pool creation is permissionless:

1. Anyone calls `MetricOmmPoolFactory.createPool` — it is `external` with
   NO access control (`MetricOmmPoolFactory.sol:204`, no `requiresAuth`).
2. They pass the shipped `DepositAllowlistExtension` (a
   beforeAddLiquidity-only extension) ordered under
   `beforeRemoveLiquidity` (order word `1` in both slots).
3. The factory accepts it — validation never probes hook implementation
   (see Vulnerability details).
4. LPs deposit normally through `addLiquidity` (the beforeAddLiquidity
   hook exists and passes).
5. Every `removeLiquidity` — full or partial, now or a year later —
   reverts. 100% of every deposit in that pool is frozen forever.

No privileged role, no oracle manipulation, no timing window, no
cooperation from anyone else is needed. The only "privilege" is being the
pool creator, which anyone can be.

## Q2: Is the impact on the program's accepted impact list? — PASS (exact)

Yes — verbatim. The Metric scope page lists under **High**:

> **Permanent freezing of funds**

This finding is that impact, measured: 100% of deposits in the
misconfigured pool are frozen, permanently, with no repair path (Part 2,
Impact). This is the first of our findings that maps onto a listed impact
exactly, at the claimed severity.

## Q3: Is the root cause in an in-scope asset? — PASS

Yes, two in-scope repos:

- `pool-contracts` — `MetricOmmPoolFactory.createPool` +
  `ValidateExtensionsConfig.validateExtensionsConfig` (the missing probe).
- `periphery-contracts` — the shipped `DepositAllowlistExtension`, the
  real extension used in the cross-check. It implements only
  `beforeAddLiquidity`; every other hook is the `BaseMetricExtension`
  default, which reverts `ExtensionNotImplemented()`.

Both repos are listed as bounty-eligible scope on the program page
("Pool Contracts" and "Periphery Contracts").

## Q4: Does it require privileged access that an attacker can't realistically get? — PASS (with the honest caveat, disclosed)

Pool creation itself needs no privilege (Q1). The realistic trigger paths
are:

- **(a) Accidental misconfiguration (realistic).** The pool curator is
  semi-trusted, and the order words are opaque packed 3-bit indices — a
  curator copying an order word from one action slot to another, or
  ordering an extension under an action it does not implement, gets no
  warning anywhere: not from the factory, not from the docs, not from
  any tool. The factory silently registers the pool as valid.
- **(b) Malicious curator (possible).** A malicious pool creator can
  deliberately deploy a pool whose exits are bricked from birth, then
  lure deposits into it (e.g. via an attractive fee/price-provider
  setup). The freeze is indistinguishable from a legitimate pool until
  someone tries to exit.

The caveat is real and is stated in the report itself (see "A note on
privilege" in Part 2): the trigger needs a misconfiguring or malicious
pool creator. It does NOT need a compromised admin, oracle, or factory
owner. The accidental case is the honest primary scenario, and the
factory is the last line of defence that could have caught it with a
one-call probe — and does not.

## Q5: Is this already known or accepted behavior? — PASS

No. Checked against:

- The published known-issues repo (`Metricxyz/Known_issues`) and the
  audit findings in the study notes (Zellic Jun + Oct 2026, Sherlock
  Jul/Sep/Oct 2026): none of them cover extension-order validation or
  hook-implementation probing. The closest relatives (Sherlock M-2
  Chainlink fees, M-5 exact-share LP extraction, M-6/M-7 addLiquidity
  cursor bounds) are different mechanisms.
- The program page does not document "an extension ordered under an
  action it does not implement bricks the pool" as accepted behaviour.
  The four shipped extensions each implement exactly one hook, and the
  factory's own validation comment says it validates "extension
  addresses, init data, and per-action call orders" — it does not claim
  to validate hook coverage, and nothing warns the creator that coverage
  is their responsibility.

## Q6: Can you prove impact beyond "technically possible"? — PASS

Measured, not hypothetical (Part 2, Evidence):

- Deposit `50,000,000` / `50,000,000` base units succeeds; full AND
  partial removal revert, now AND after `+365 days`.
- Position shares unchanged (`10,000,000` in bin -5); pool balances
  unchanged at exactly `50,000,000` / `50,000,000`. **100% frozen.**
- Control with a full extension ordered the same way removes
  `50,000,000` / `50,000,000` and empties the position — the brick is
  caused by the missing hook, not by the order.
- No repair path verified by test + code (pause/unpause, factory
  rescue, fee collection, swap exit — all fail or do not touch
  principal).
- Cross-check with the REAL shipped `DepositAllowlistExtension`
  reproduces the brick exactly (`ExtensionNotImplemented`, same amounts,
  same permanence). The mock result is not a mock artifact.

## Q7: Is this a known-invalid bug class? — PASS

No. It is not a duplicate of a known issue, not a griefing-only finding
(the freeze is permanent and total, not a delay or a fee), not a
front-running/MEV observation, and not a finding that requires
out-of-scope behaviour. It is a validation gap in in-scope code with a
listed impact.

## Gate result: PASS (7/7)

---

# Part 2 — Report (Immunefi submission draft)

## Title

Ordered extension need not implement its hook: a mismatched order
permanently bricks `removeLiquidity` (permanent freezing of funds)

## Severity: High

Maps exactly onto the listed Metric High impact **"Permanent freezing of
funds"**.

**A note on the dollar tier:** the High / Medium / Low dollar tiers were
NOT visible in the program-page text fetch (rendered as SVG images), so
this draft does not claim a dollar figure for High. Critical is 20% of
funds directly affected, max $500,000, min $50,000. Re-check the live
program page for the High tier before submitting.

## Summary

`MetricOmmPoolFactory.createPool` validates extension orders for counts,
duplicates, zero addresses and indices only. It never probes whether an
extension ordered for an action implements that action's hook. A pool
created with a beforeAddLiquidity-only extension — e.g. the shipped
`DepositAllowlistExtension` — ordered under `beforeRemoveLiquidity`
accepts deposits, but every `removeLiquidity` reverts forever. Extension
orders and addresses are pool immutables, so there is no way to fix the
pool afterwards: 100% of LP funds in it are permanently frozen.

Pool creation is permissionless (`createPool` has no access control), so
anyone can create such a pool — by accident (the order words are opaque
packed 3-bit indices and nothing warns the creator) or deliberately, to
lure deposits into a pool whose exits are bricked from birth.

## Impact

- **Permanent freezing of funds (listed High impact).** Every token
  deposited into a misconfigured pool is locked forever: `removeLiquidity`
  reverts on every path (full, partial, now, +365 days). Measured: deposit
  `50,000,000` / `50,000,000` base units, position shares unchanged at
  `10,000,000`, pool balances unchanged at exactly `50,000,000` /
  `50,000,000` after a year of simulated time.
- **The freeze is total, not partial.** It is not a delay, a fee, or a
  haircut: the exit function itself reverts before any accounting, so no
  fraction of the deposit can ever leave through the pool.
- **No repair path exists.**
  - Extension orders and addresses are pool **immutables**
    (`ExtensionCalling` constructor: `EXTENSION_1..7`,
    `BEFORE_REMOVE_LIQUIDITY_ORDER`). No factory or pool-admin function
    changes them; there is not even a `setPoolAdmin` function — the admin
    is fixed at creation.
  - `protocolPausePool` + `protocolUnpausePool` do not un-brick the pool
    (tested).
  - The factory's `collectTokens` / `collectEth`
    (`MetricOmmPoolFactory.sol:337,348`) only move tokens held by the
    **factory itself** (`balanceOf(address(this))`) — they cannot touch
    pool funds.
  - `collectFees` only collects accrued fees, never principal.
  - Swaps still execute on the bricked pool, but LP shares are not
    transferable and trading does not touch the position — there is no
    exit via swap (tested).
- **Blast radius is one pool per misconfiguration, but the loss inside
  it is 100%.** Any pool created with a mismatched order is affected;
  correctly-configured pools are unaffected. The loss scales with
  whatever LPs deposit before anyone discovers the exit is bricked —
  and nothing at creation signals that it is.

### A note on privilege (for triage — please read)

The trigger needs a pool creator who misconfigures the order or does so
maliciously; the pool curator is semi-trusted. We disclose this plainly
rather than hiding it. Two points in favour of High despite that:

1. **The accidental case is realistic.** Orders are opaque packed 3-bit
   words, the factory performs no probe, and nothing at creation warns
   the creator. The factory is the natural and only checkpoint that
   could have caught this with a single static call — and it does not.
2. **Pool creation is permissionless.** No allowlist, no role, no
   review stands between an attacker and a bricked pool. A malicious
   creator needs nothing but a deployment transaction, and the resulting
   pool is indistinguishable from a legitimate one until the first exit
   attempt.

## Vulnerability details

### The validation gap

`MetricOmmPoolFactory.createPool`
(`contracts/MetricOmmPoolFactory.sol:204`) is `external` with no access
control. It calls
`ValidateExtensionsConfig.validateExtensionsConfig(params.extensions,
params.extensionOrders, params.extensionInitData)` (`:215-217`), then
only calls `initialize` on each extension (`:269-273`).

`validateExtensionsConfig`
(`contracts/libraries/ValidateExtensionsConfig.sol`) checks exactly four
things:

- at most 7 extensions; `extensionInitData.length == extensions.length`;
- no zero addresses, no duplicate addresses;
- orders are non-zero;
- each order word contains only indices `1..extensionCount`, with no
  duplicates (`_validateExtensionOrder`, packed 3-bit groups).

It never calls — or even static-calls — an ordered extension to check
that it implements the hook it is ordered for. `initialize` succeeding
proves nothing about hook coverage: the shipped
`DepositAllowlistExtension.initialize` succeeds while the contract
implements only `beforeAddLiquidity`.

### Why removal then reverts forever

`removeLiquidity` (`contracts/MetricOmmPool.sol:217`) calls
`_beforeRemoveLiquidity` (`:225`) before any accounting. That walks
`BEFORE_REMOVE_LIQUIDITY_ORDER`
(`contracts/ExtensionCalling.sol:125-136`) and calls each ordered
extension's `beforeRemoveLiquidity` via `CallExtension.callExtension`
(`contracts/libraries/CallExtension.sol:9`).

- **Real-extension shape:** `DepositAllowlistExtension` inherits
  `BaseMetricExtension`, whose default hooks are `onlyPool` + revert
  `ExtensionNotImplemented()`. The revert data is non-empty, so
  `callExtension` re-reverts it verbatim.
- **No-fallback shape:** an extension with no such function at all fails
  the call with empty returndata, and `callExtension` reverts
  `ExtensionCallFailed()` (`:17`).

Either way the whole `removeLiquidity` call reverts, before any state
change. The hook is called on every removal, so the revert is
permanent — there is no code path that skips it, and the order word
that causes it is immutable.

### Code paths (repo `pool-contracts` @ `ddf8ae0`, `periphery-contracts` @ `5ceaec3`)

- `contracts/libraries/ValidateExtensionsConfig.sol` —
  `validateExtensionsConfig`, `_validateExtensionOrder` (counts / dupes /
  zero / indices only).
- `contracts/MetricOmmPoolFactory.sol:204` — `createPool`, permissionless;
  `:215-217` validation call; `:269-273` `initialize` calls.
- `contracts/ExtensionCalling.sol:21,33,42,51` — `EXTENSION_1..7` and
  `BEFORE_REMOVE_LIQUIDITY_ORDER` are immutables set in the constructor.
- `contracts/MetricOmmPool.sol:217,225` — `removeLiquidity` calls
  `_beforeRemoveLiquidity` first.
- `contracts/ExtensionCalling.sol:125-136` — `_beforeRemoveLiquidity`
  walks the order word.
- `contracts/libraries/CallExtension.sol:5,9,17` —
  `ExtensionCallFailed`, `callExtension` re-revert behaviour.
- `periphery/contracts/extensions/DepositAllowlistExtension.sol` — the
  shipped extension; implements `beforeAddLiquidity` only.
- `periphery/contracts/extensions/base/BaseMetricExtension.sol` — default
  hooks revert `ExtensionNotImplemented()`.

### Why this is not a known issue

Checked against the published known-issues repo and the Zellic (Jun +
Oct 2026) and Sherlock (Jul / Sep / Oct 2026) audit findings: no
finding covers extension-order validation or hook-implementation
probing. The factory's own validation comment describes validating
"extension addresses, init data, and per-action call orders" — it does
not claim hook coverage, and no document warns creators that coverage
is their responsibility.

## Steps to reproduce

### 1. Clone the PoC and run the tests

```bash
git clone https://github.com/Anyeps/metric-extension-hook-pool-brick-poc
cd metric-extension-hook-pool-brick-poc
forge install foundry-rs/forge-std@0e44f85 --no-commit
forge install OpenZeppelin/openzeppelin-contracts@dde766bd --no-commit
forge test --match-contract "MP13ExtensionBrickTest|MP13RealExtensionTest" -vv
```

Expected: **7 passed, 0 failed** (6 brick tests + 1 real-extension
cross-check). No fork URL, no RPC, no mainnet state: the bug is pure
factory-validation logic, tested by local deployment of the exact repo
code with the repo's own harness (`MockOracle` / `MockERC20` /
`TestCaller`). First build is slow (`via_ir` + optimizer); the suite
itself runs in <100 ms.

### 2. What the tests show

`test/MP13ExtensionBrick.t.sol` (`MP13ExtensionBrickTest`):

1. `test_1_factoryAcceptsMismatchedOrder` — `createPool` with the
   beforeAddLiquidity-only extension ordered under
   `beforeRemoveLiquidity` succeeds; `factory.isPool(pool)` is true.
2. `test_2_addWorksRemoveRevertsForever` — deposit of `50,000,000` /
   `50,000,000` succeeds; full removal reverts
   `ExtensionNotImplemented`; after `vm.warp(+365 days)` full AND half
   removal still revert; position shares unchanged at `10,000,000`;
   pool balances unchanged.
3. `test_3_noFallbackExtension_revertsExtensionCallFailed` — the
   no-fallback shape: removal reverts `ExtensionCallFailed`.
4. `test_4_control_fullExtension_removesNormally` — same order, same
   amounts, a full extension: removal returns `50,000,000` /
   `50,000,000` and the position empties to 0. The brick is caused by
   the missing hook, not by the order.
5. `test_5_noRepairPath_adminActionsDoNotUnbrick` — pause + unpause
   does not un-brick; removal still reverts.
6. `test_6_brickedPool_swapStillWorks` — swaps still execute on the
   bricked pool, but the LP position is untouched: no exit via trading.

`test/MP13RealExtension.t.sol` (`MP13RealExtensionTest`) — the same
scenario with the REAL shipped `DepositAllowlistExtension`
(`periphery-contracts` @ `5ceaec3`), allowlist opened via
`setAllowAllDepositors`: factory accepts, deposit `50,000,000` /
`50,000,000` succeeds, removal reverts
`BaseMetricExtension.ExtensionNotImplemented`, still reverts at +365
days, position and balances intact.

### 3. Minimal manual repro (no test file needed)

1. Deploy `MetricOmmPoolFactory` + `MetricOmmPoolDeployer` (or use the
   repo harness).
2. Deploy `DepositAllowlistExtension(factory)`.
3. `createPool` with `extensions = [ext]`,
   `extensionOrders.beforeAddLiquidity = 1`,
   `extensionOrders.beforeRemoveLiquidity = 1`.
4. `addLiquidity` as an allowlisted LP — succeeds.
5. `removeLiquidity` for any amount — reverts
   `ExtensionNotImplemented()`, forever.

## Suggested fix

In `createPool` (or in `validateExtensionsConfig`), probe each ordered
extension for the hooks it is ordered for — e.g. a static call to the
hook with dummy arguments, or an `ERC-165`-style interface check — and
revert pool creation when an ordered extension does not implement its
hook. A cheaper alternative is a view helper that creators must call
before creation, but a factory-side probe is the only check that cannot
be skipped by accident. Note the probe must tolerate extensions whose
hooks legitimately revert on dummy input; the cleanest signal is
whether the function selector exists (extcode / `supportsInterface`)
rather than whether a dummy call succeeds.

## PoC repository

https://github.com/Anyeps/metric-extension-hook-pool-brick-poc

Contents: this report draft (`REPORT-DRAFT.md`), findings
(`FINDINGS.md`), the two Foundry test suites, and the exact repo code
under test vendored verbatim — `contracts/` is `pool-contracts` @
`ddf8ae0`, `periphery/` is `periphery-contracts` @ `5ceaec3`. No fork,
no mainnet interaction, no secrets.

## Payout

- **Wallet:** `0x45859319d9a362f2146d0431dc30ab8f0ef1be73`
- **Program:** Metric (Immunefi) — KYC not required.
- **Severity claimed:** High — listed impact "Permanent freezing of
  funds". Dollar tier for High was not visible on the program page at
  research time (SVG); triage to confirm against the live tier table.

---

*Draft prepared 2026-11-15. NOT submitted. Submission blocked by the
Immunefi Novice 100-credit fee; waiting for the Studio wave verdict,
same as the GMX G-P1-2(a) and G-P0-7 drafts.*
