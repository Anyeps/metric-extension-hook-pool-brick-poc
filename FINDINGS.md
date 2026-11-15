# M-P1-3 — FINDINGS

## Verdict: FOUND

**Ordered extension need not implement its hook: a mismatched order
permanently bricks `removeLiquidity`.**

- Date: 2026-11-15 ~13:10 WIB
- Repos: `pool-contracts` ddf8ae0, `periphery-contracts` 5ceaec3
  (clones in `~/workspace/hunts/metric/repos/`)
- Environment: **local deploy, no fork** (see § Environment). Forge 1.9.0,
  solc 0.8.35.
- Tests: **6/6 pass** (`MP13ExtensionBrickTest`) + **1/1 pass**
  real-extension cross-check (`MP13RealExtensionTest`, real shipped
  `DepositAllowlistExtension`).

## What was tested

(a) **Factory accepts the mismatched order.** `createPool` with the
beforeAddLiquidity-only extension ordered under `beforeRemoveLiquidity`
succeeds; `factory.isPool(pool)` is true. Pool created at
`0x3ecD294Ab45b1523cDdcADAF2F0983D1791bcB8F` (test run).
Root cause, read in code: `ValidateExtensionsConfig.validateExtensionsConfig`
checks counts / duplicates / zero / indices only — it never probes
whether an ordered extension implements the hook. `createPool` calls it
and then only `initialize` on each extension
(`MetricOmmPoolFactory.sol:215-217,269-273`).

(b) **Deposit works, removal reverts forever.** LP adds 10,000,000 shares
over bins -5..4: `amount0Added = amount1Added = 50,000,000` base units
(MockERC20, 18 decimals). `removeLiquidity` reverts:

- Real-extension shape: `ExtensionNotImplemented` — the
  `BaseMetricExtension` default hook, bubbled verbatim by
  `CallExtension.callExtension` (non-empty revert data is re-reverted).
- No-fallback shape: `ExtensionCallFailed` — hook call fails with empty
  returndata.
- Full removal AND half removal, now AND after `vm.warp(+365 days)`:
  still reverts. Position shares unchanged (`10,000,000` in bin -5);
  pool balances unchanged at exactly `50,000,000` / `50,000,000`.
  **100% of the deposit is frozen.**

(c) **Control: a full extension removes normally.** Same order, same
amounts, `MockMetricExtension` (implements all hooks): removal returns
`50,000,000` / `50,000,000` and the position empties to 0. The brick is
caused by the missing hook, not by the order itself.

(d) **No repair path.** Verified by code + test:

- Extension orders and addresses are pool **immutables**
  (`ExtensionCalling` constructor; `BEFORE_REMOVE_LIQUIDITY_ORDER`,
  `EXTENSION_1..7`). No factory or pool-admin function changes them.
  There is not even a `setPoolAdmin` function — the admin is fixed at
  creation.
- `protocolPausePool` + `protocolUnpausePool` (test 5): removal still
  reverts afterwards.
- Factory rescue (`rescueERC20`/`rescueETH`,
  `IMetricOmmPoolFactoryOwner`) covers **factory-held stray funds only**,
  not pool funds.
- `collectFees` only collects accrued fees, never principal.
- **No exit via swap** (test 6): swaps still execute on the bricked pool,
  but LP shares are not transferable and the position is untouched by
  trading — swapping cannot redeem shares.

## Cross-check with the real extension

`MP13RealExtensionTest` (scratch copy of `periphery-contracts`, with
`lib/metric-core` symlinked to the pinned `pool-contracts` repo) uses
the **real shipped `DepositAllowlistExtension`** (5ceaec3), ordered under
`beforeRemoveLiquidity`, allowlist opened via `setAllowAllDepositors`:
factory accepts, deposit `50,000,000` / `50,000,000` succeeds, removal
reverts `BaseMetricExtension.ExtensionNotImplemented`, still reverts at
+365 days, position and balances intact. The mock-based result is not a
mock artifact.

## Environment note — why local deploy, not a fork

The task allows a fork or a local deploy. A fork adds nothing here: the
bug is pure factory-validation logic on the exact repo code, exercisable
with the repo's own harness (`MockOracle` / `MockERC20` / `TestCaller`).
No live state is involved (no oracle feeds, no existing pools). The
deployed factory on all 10 chains is the same code at the same CREATE3
addresses (per `program.md`); bytecode-equality against a live address
was not re-checked — the factory address is not recorded in the study
notes, and the logic under test is identical in the repo either way.

## Severity assessment (for the report phase — NOT submitted)

- **High, mapping exactly onto the listed Immunefi Metric High impact
  "Permanent freezing of funds".** The frozen amount is 100% of whatever
  LPs deposited into the misconfigured pool.
- **Caveats for triage (honest):** the trigger needs creator
  misconfiguration or a malicious creator — the pool curator is
  semi-trusted. The accidental case is realistic: orders are opaque
  packed 3-bit words, the factory does not probe, and nothing at creation
  warns the creator. A malicious creator can also lure deposits into a
  pool whose exits are bricked from birth.
- The deposit size in the tests (50,000,000 base units) is a harness
  scaling artifact (`initialScaledAmount0PerE18Shares = 1e18`); the
  frozen fraction is 100% at any deposit size.

## How to reproduce

See `README.md`. `forge test --match-contract MP13ExtensionBrickTest -vv`
in `pool-contracts/test/` (copy the test file there first). First build
is slow (via_ir + optimizer); the suite itself runs in <100 ms.
