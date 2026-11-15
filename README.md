# Metric — Ordered extension need not implement its hook: pool permanently bricks `removeLiquidity`

**Finding:** `MetricOmmPoolFactory.createPool` validates extension orders for
counts, duplicates, zero addresses and indices only
(`ValidateExtensionsConfig.validateExtensionsConfig`). It never probes
whether an extension ordered for an action implements that action's hook.
A pool created with a beforeAddLiquidity-only extension — e.g. the shipped
`DepositAllowlistExtension` — ordered under `beforeRemoveLiquidity`
accepts deposits, but every `removeLiquidity` reverts forever. Extension
orders and addresses are pool immutables, so there is no way to fix the
pool afterwards: **100% of LP funds in it are permanently frozen.**

**Severity: High** — maps exactly onto the listed Immunefi Metric High
impact **"Permanent freezing of funds"**.

**Measured (local deploy of the exact repo code, no fork):** deposit
`50,000,000` / `50,000,000` base units succeeds; full AND partial removal
revert, now AND after `+365 days`; position shares unchanged at
`10,000,000`; pool balances unchanged. A control with a full extension
ordered the same way removes `50,000,000` / `50,000,000` and empties the
position — the brick is caused by the missing hook, not by the order.
Pause/unpause, factory rescue, fee collection and swap-exit all fail to
un-brick it. Cross-checked with the REAL shipped
`DepositAllowlistExtension` (same result, same error).

Pool creation is permissionless (`createPool` has no access control), so
anyone can create such a pool — by accident (order words are opaque
packed 3-bit indices and nothing warns the creator) or deliberately, to
lure deposits into a pool whose exits are bricked from birth.

## Files

- `REPORT-DRAFT.md` — full Immunefi report draft (severity High), incl.
  the 7-question gate, the privilege caveat stated plainly, and the
  suggested fix.
- `FINDINGS.md` — verdict + measured evidence (6/6 + 1/1 tests).
- `test/MP13ExtensionBrick.t.sol` — Foundry tests (6 tests).
- `test/MP13RealExtension.t.sol` — cross-check with the REAL shipped
  `DepositAllowlistExtension` (1 test).
- `contracts/` — `pool-contracts` @ `ddf8ae0`, vendored verbatim.
- `periphery/` — `periphery-contracts` @ `5ceaec3`, vendored verbatim.
- `test/MetricOmmPool.base.t.sol`, `test/PoolStateTestLib.sol`,
  `test/ExtensionOrderTestLib.sol`, `test/FactoryFeeCapsStub.sol`,
  `test/PoolInitPreprocessor.sol`, `test/mocks/` — the repo's own test
  harness, vendored verbatim.

## Reproduce

```bash
git clone https://github.com/Anyeps/metric-extension-hook-pool-brick-poc
cd metric-extension-hook-pool-brick-poc
forge install foundry-rs/forge-std@0e44f85 --no-commit
forge install OpenZeppelin/openzeppelin-contracts@dde766bd --no-commit
forge test --match-contract "MP13ExtensionBrickTest|MP13RealExtensionTest" -vv
```

Expected: **7 passed, 0 failed.** No fork URL, no RPC, no mainnet state:
the bug is pure factory-validation logic, tested by local deployment of
the exact repo code with the repo's own harness (`MockOracle` /
`MockERC20` / `TestCaller`). First build is slow (`via_ir` +
optimizer); the suite itself runs in <100 ms. Requires Foundry
(`forge`) and solc 0.8.35 (set in `foundry.toml`).

## Mocks vs the real extension

The PoC's `BeforeAddOnlyExtension` is a behaviour-identical stand-in for
the shipped periphery `DepositAllowlistExtension`: that contract inherits
`BaseMetricExtension`, whose default hooks are `onlyPool` + revert
`ExtensionNotImplemented()` — the mock reproduces that surface exactly
(same error selector). `NoHookExtension` reproduces the no-fallback shape
(hook call fails with empty returndata -> `ExtensionCallFailed`). The
real-extension test uses the actual shipped contract, not a mock.

## Notes

- The vendored Metric code retains its original SPDX headers and
  licenses (see `licenses/`). Upstream repos:
  `pool-contracts` @ `ddf8ae0`, `periphery-contracts` @ `5ceaec3`.
- The High / Medium / Low dollar tiers were not visible on the Metric
  program page at research time (rendered as SVG); the draft claims the
  listed impact, not a dollar figure.
- Metric program: https://immunefi.com/bug-bounty/metric/information/
  (KYC not required; PoC required; no mainnet testing).

## Status

Report draft prepared 2026-11-15. **NOT submitted** — submission is
blocked by the Immunefi Novice 100-credit fee; waiting for the Studio
wave verdict (same as the GMX drafts).
