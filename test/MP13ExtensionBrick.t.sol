// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title M-P1-3 PoC — ordered extension need not implement its hook
/// @notice Factory validation checks counts / duplicates / zero / indices
///         ONLY (ValidateExtensionsConfig.validateExtensionsConfig) and
///         never probes whether an ordered extension implements the hook.
///         A pool created with a beforeAddLiquidity-only extension ordered
///         under beforeRemoveLiquidity ACCEPTS deposits, but every
///         removeLiquidity reverts forever: permanent freezing of LP funds.
/// @dev Test-only file. To run, copy into pool-contracts/test/ and run:
///         forge test --match-contract MP13ExtensionBrickTest -vv
///      Local deployment of the exact repo code (pool-contracts ddf8ae0,
///      periphery-contracts 5ceaec3). No fork, no mainnet state: the bug is
///      pure factory-validation logic, exercisable with the repo's own
///      harness (MockOracle / MockERC20 / TestCaller).
///      The mocks below are behaviour-identical stand-ins for the shipped
///      periphery DepositAllowlistExtension: it inherits BaseMetricExtension,
///      whose default hooks are `onlyPool` + revert ExtensionNotImplemented().
///      BeforeAddOnlyExtension reproduces that surface exactly (same error
///      selector, same onlyPool gate). NoHookExtension reproduces the
///      no-fallback shape (hook call fails with empty returndata).

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MetricOmmPoolBaseTest} from "./MetricOmmPool.base.t.sol";
import {MetricOmmPoolFactory} from "../contracts/MetricOmmPoolFactory.sol";
import {MetricOmmPoolDeployer} from "../contracts/MetricOmmPoolDeployer.sol";
import {PoolParameters} from "../contracts/types/FactoryOperation.sol";
import {ExtensionOrders} from "../contracts/types/PoolExtensionsConfig.sol";
import {ExtensionOrderTestLib} from "./ExtensionOrderTestLib.sol";
import {LiquidityDelta} from "../contracts/types/PoolOperation.sol";
import {IMetricOmmExtensions} from "../contracts/interfaces/extensions/IMetricOmmExtensions.sol";
import {MockMetricExtension} from "./mocks/MockMetricExtension.sol";
import {CallExtension} from "../contracts/libraries/CallExtension.sol";
import {PoolStateTestLib} from "./PoolStateTestLib.sol";

/// @notice Mirrors the shipped periphery DepositAllowlistExtension hook
///         surface: implements initialize + beforeAddLiquidity only; every
///         other hook reverts ExtensionNotImplemented(), exactly like the
///         BaseMetricExtension defaults it inherits.
contract BeforeAddOnlyExtension is IMetricOmmExtensions {
  error ExtensionNotImplemented();
  error OnlyPool();

  address public boundPool;

  function initialize(address pool, bytes calldata) external returns (bytes4) {
    boundPool = pool;
    return IMetricOmmExtensions.initialize.selector;
  }

  function beforeAddLiquidity(address, address, uint80, LiquidityDelta calldata, bytes calldata)
    external
    view
    returns (bytes4)
  {
    if (msg.sender != boundPool) revert OnlyPool();
    return IMetricOmmExtensions.beforeAddLiquidity.selector;
  }

  function afterAddLiquidity(address, address, uint80, LiquidityDelta calldata, uint256, uint256, bytes calldata)
    external
    view
    returns (bytes4)
  {
    if (msg.sender != boundPool) revert OnlyPool();
    revert ExtensionNotImplemented();
  }

  function beforeRemoveLiquidity(address, address, uint80, LiquidityDelta calldata, bytes calldata)
    external
    view
    returns (bytes4)
  {
    if (msg.sender != boundPool) revert OnlyPool();
    revert ExtensionNotImplemented();
  }

  function afterRemoveLiquidity(address, address, uint80, LiquidityDelta calldata, uint256, uint256, bytes calldata)
    external
    view
    returns (bytes4)
  {
    if (msg.sender != boundPool) revert OnlyPool();
    revert ExtensionNotImplemented();
  }

  function beforeSwap(address, address, bool, int128, uint128, uint256, uint128, uint128, uint128, bytes calldata)
    external
    view
    returns (bytes4)
  {
    if (msg.sender != boundPool) revert OnlyPool();
    revert ExtensionNotImplemented();
  }

  function afterSwap(
    address,
    address,
    bool,
    int128,
    uint128,
    uint256,
    uint256,
    uint128,
    uint128,
    uint128,
    int128,
    int128,
    uint256,
    bytes calldata
  ) external view returns (bytes4) {
    if (msg.sender != boundPool) revert OnlyPool();
    revert ExtensionNotImplemented();
  }
}

/// @notice Implements initialize + beforeAddLiquidity only and has NO
///         fallback: any other hook call fails with empty returndata.
contract NoHookExtension {
  function initialize(address, bytes calldata) external pure returns (bytes4) {
    return IMetricOmmExtensions.initialize.selector;
  }

  function beforeAddLiquidity(address, address, uint80, LiquidityDelta calldata, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return IMetricOmmExtensions.beforeAddLiquidity.selector;
  }
}

contract MP13ExtensionBrickTest is MetricOmmPoolBaseTest {
  MetricOmmPoolFactory internal mp13Factory;

  int16 internal constant LO = -5;
  int16 internal constant HI = 4;
  uint104 internal constant SHARES = 10_000_000;
  uint80 internal constant SALT = 0;

  function setUp() public override {
    super.setUp();
    mp13Factory = new MetricOmmPoolFactory(address(this), address(this), 0, 0, type(uint16).max);
    MetricOmmPoolDeployer deployer = new MetricOmmPoolDeployer(address(mp13Factory));
    mp13Factory.setPoolDeployer(address(deployer));
  }

  function _brickParams(address extension, bytes32 salt) internal returns (PoolParameters memory params) {
    address[] memory extensions = new address[](1);
    extensions[0] = extension;
    bytes[] memory initData = new bytes[](1);
    ExtensionOrders memory orders;
    orders.beforeAddLiquidity = ExtensionOrderTestLib.encodeExtensionOrder(1, 0, 0, 0, 0, 0, 0);
    orders.beforeRemoveLiquidity = ExtensionOrderTestLib.encodeExtensionOrder(1, 0, 0, 0, 0, 0, 0);
    params = PoolParameters({
      token0: address(token0),
      token1: address(token1),
      priceProvider: address(oracle),
      extensions: extensions,
      extensionOrders: orders,
      extensionInitData: initData,
      priceProviderTimelock: type(uint256).max,
      admin: address(this),
      initialScaledAmount0PerE18Shares: 1e18,
      initialScaledAmount1PerE18Shares: 1e18,
      minimalOperationalLiquidity: 1e6,
      protocolSpreadFeeE6: 0,
      adminSpreadFeeE6: ADMIN_FEE,
      protocolNotionalFeeE8: 0,
      adminNotionalFeeE8: 0,
      adminFeeDestination: makeAddr("adminFeeDest"),
      curBinDistFromProvidedPriceE6: 0,
      nonNegativeBinDataArray: _createBinDataArray(),
      negativeBinDataArray: _createBinDataArray(),
      salt: salt,
      bidAskRefAsymmetryX8: type(uint16).max
    });
    oracle.setTokens(params.token0, params.token1);
  }

  function _addTo(address poolAddr, uint256 userIndex) internal returns (uint256 a0, uint256 a1) {
    LiquidityDelta memory deltas = _rangeDeltas(LO, HI, SHARES);
    vm.prank(users[userIndex]);
    return callers[userIndex].addLiquidity(poolAddr, SALT, deltas);
  }

  function _removeFrom(address poolAddr, uint256 userIndex, uint104 shares) internal returns (uint256 r0, uint256 r1) {
    LiquidityDelta memory deltas = _rangeDeltas(LO, HI, shares);
    vm.prank(users[userIndex]);
    return callers[userIndex].removeLiquidity(poolAddr, SALT, deltas);
  }

  // (a) factory accepts the mismatched order.
  function test_1_factoryAcceptsMismatchedOrder() public {
    BeforeAddOnlyExtension ext = new BeforeAddOnlyExtension();
    address poolAddr = mp13Factory.createPool(_brickParams(address(ext), keccak256("MP13-1")));
    assertTrue(mp13Factory.isPool(poolAddr), "factory must register the pool");
    console.log("brick pool:", poolAddr);
  }

  // (b) deposits work, removal reverts forever — full and partial, now and +365d.
  function test_2_addWorksRemoveRevertsForever() public {
    BeforeAddOnlyExtension ext = new BeforeAddOnlyExtension();
    address poolAddr = mp13Factory.createPool(_brickParams(address(ext), keccak256("MP13-2")));
    _approveUsersForPool(poolAddr);

    (uint256 a0, uint256 a1) = _addTo(poolAddr, 1);
    assertGt(a0, 0, "deposit token0");
    assertGt(a1, 0, "deposit token1");
    console.log("deposited token0:", a0);
    console.log("deposited token1:", a1);
    assertGe(token0.balanceOf(poolAddr), a0, "pool holds the deposit");
    assertGe(token1.balanceOf(poolAddr), a1, "pool holds the deposit");

    vm.expectRevert(BeforeAddOnlyExtension.ExtensionNotImplemented.selector);
    _removeFrom(poolAddr, 1, SHARES);

    vm.warp(block.timestamp + 365 days);
    vm.expectRevert(BeforeAddOnlyExtension.ExtensionNotImplemented.selector);
    _removeFrom(poolAddr, 1, SHARES);
    vm.expectRevert(BeforeAddOnlyExtension.ExtensionNotImplemented.selector);
    _removeFrom(poolAddr, 1, SHARES / 2);

    // position and pool balances unchanged: funds are frozen, not moved.
    assertEq(PoolStateTestLib.positionBinShares(poolAddr, address(callers[1]), SALT, LO), SHARES);
    assertEq(token0.balanceOf(poolAddr), a0, "locked token0 unchanged");
    assertEq(token1.balanceOf(poolAddr), a1, "locked token1 unchanged");
    console.log("locked token0 after 365d:", token0.balanceOf(poolAddr));
    console.log("locked token1 after 365d:", token1.balanceOf(poolAddr));
  }

  // Second shape of the same root cause: no hook at all -> ExtensionCallFailed.
  function test_3_noFallbackExtension_revertsExtensionCallFailed() public {
    NoHookExtension ext = new NoHookExtension();
    address poolAddr = mp13Factory.createPool(_brickParams(address(ext), keccak256("MP13-3")));
    _approveUsersForPool(poolAddr);
    (uint256 a0, uint256 a1) = _addTo(poolAddr, 1);
    assertGt(a0, 0);
    assertGt(a1, 0);

    vm.expectRevert(CallExtension.ExtensionCallFailed.selector);
    _removeFrom(poolAddr, 1, SHARES);
  }

  // (c) control: a full extension ordered the same way removes normally.
  function test_4_control_fullExtension_removesNormally() public {
    MockMetricExtension ext = new MockMetricExtension();
    address poolAddr = mp13Factory.createPool(_brickParams(address(ext), keccak256("MP13-4")));
    _approveUsersForPool(poolAddr);
    (uint256 a0, uint256 a1) = _addTo(poolAddr, 1);
    (uint256 r0, uint256 r1) = _removeFrom(poolAddr, 1, SHARES);
    assertGt(r0, 0, "exit returns token0");
    assertGt(r1, 0, "exit returns token1");
    assertEq(PoolStateTestLib.positionBinShares(poolAddr, address(callers[1]), SALT, LO), 0, "position emptied");
    console.log("control removed token0:", r0, "of deposited:", a0);
    console.log("control removed token1:", r1, "of deposited:", a1);
  }

  // (d) no repair: pause/unpause does not un-brick; the pool is otherwise
  // alive (swaps still work), so the freeze is removal-specific and the LP
  // cannot exit via swap either (shares are not transferable).
  function test_5_noRepairPath_adminActionsDoNotUnbrick() public {
    BeforeAddOnlyExtension ext = new BeforeAddOnlyExtension();
    address poolAddr = mp13Factory.createPool(_brickParams(address(ext), keccak256("MP13-5")));
    _approveUsersForPool(poolAddr);
    _addTo(poolAddr, 1);

    mp13Factory.protocolPausePool(poolAddr);
    mp13Factory.protocolUnpausePool(poolAddr);

    vm.expectRevert(BeforeAddOnlyExtension.ExtensionNotImplemented.selector);
    _removeFrom(poolAddr, 1, SHARES);
  }

  function test_6_brickedPool_swapStillWorks() public {
    BeforeAddOnlyExtension ext = new BeforeAddOnlyExtension();
    address poolAddr = mp13Factory.createPool(_brickParams(address(ext), keccak256("MP13-6")));
    _approveUsersForPool(poolAddr);
    _addTo(poolAddr, 1);

    (int256 d0,) = _swapOnPool(poolAddr, 0, users[0], false, int128(1000), type(uint128).max);
    assertLt(d0, 0, "swap still executes on the bricked pool");

    // the LP position is untouched by the swap: no exit via trading.
    assertEq(PoolStateTestLib.positionBinShares(poolAddr, address(callers[1]), SALT, LO), SHARES);
  }
}
