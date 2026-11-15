// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @notice Cross-check for M-P1-3 using the REAL shipped
///         DepositAllowlistExtension (periphery-contracts 5ceaec3) against
///         the REAL factory (pool-contracts ddf8ae0). Scratch-only test:
///         run in a copy of periphery-contracts with lib/metric-core
///         symlinked to the pool-contracts repo.
///         forge test --match-contract MP13RealExtensionTest -vv
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MetricOmmPoolFactory} from "@metric-core/MetricOmmPoolFactory.sol";
import {MetricOmmPoolDeployer} from "@metric-core/MetricOmmPoolDeployer.sol";
import {PoolParameters} from "@metric-core/types/FactoryOperation.sol";
import {ExtensionOrders} from "@metric-core/types/PoolExtensionsConfig.sol";
import {LiquidityDelta} from "@metric-core/types/PoolOperation.sol";
import {DepositAllowlistExtension} from "../periphery/extensions/DepositAllowlistExtension.sol";
import {BaseMetricExtension} from "../periphery/extensions/base/BaseMetricExtension.sol";
import {MockERC20} from "@metric-core-test/mocks/MockERC20.sol";
import {MockOracle} from "@metric-core-test/mocks/MockOracle.sol";
import {TestCaller} from "@metric-core-test/mocks/TestCaller.sol";
import {PoolStateTestLib} from "@metric-core-test/PoolStateTestLib.sol";

contract MP13RealExtensionTest is Test {
  MetricOmmPoolFactory internal factory;
  MockERC20 internal token0;
  MockERC20 internal token1;
  MockOracle internal oracle;
  DepositAllowlistExtension internal ext;
  TestCaller internal caller;
  address internal user;

  function setUp() public {
    token0 = new MockERC20("Token0", "TK0", 18);
    token1 = new MockERC20("Token1", "TK1", 18);
    oracle = new MockOracle();
    oracle.setBidAndAskPrice(uint128(2 ** 64), uint128(2 ** 64 + 1));
    oracle.setTokens(address(token0), address(token1));

    factory = new MetricOmmPoolFactory(address(this), address(this), 0, 0, type(uint16).max);
    MetricOmmPoolDeployer deployer = new MetricOmmPoolDeployer(address(factory));
    factory.setPoolDeployer(address(deployer));

    ext = new DepositAllowlistExtension(address(factory));

    user = makeAddr("user");
    caller = new TestCaller(user, address(factory));
    token0.mint(address(caller), 1_000_000e18);
    token1.mint(address(caller), 1_000_000e18);
  }

  function _binData() internal pure returns (uint256[] memory arr) {
    arr = new uint256[](1);
    uint256 packed;
    for (uint256 j; j < 5; j++) {
      packed |= uint256(uint48(100)) << (j * 48);
    }
    arr[0] = packed;
  }

  function _rangeDeltas(int16 lo, int16 hi, uint256 shares) internal pure returns (LiquidityDelta memory d) {
    uint256 n = uint256(int256(hi) - int256(lo) + 1);
    int256[] memory idxs = new int256[](n);
    uint256[] memory sh = new uint256[](n);
    for (uint256 i; i < n; i++) {
      idxs[i] = int256(lo) + int256(i);
      sh[i] = shares;
    }
    return LiquidityDelta({binIdxs: idxs, shares: sh});
  }

  function test_realDepositAllowlistExtension_bricksRemoval() public {
    address[] memory extensions = new address[](1);
    extensions[0] = address(ext);
    bytes[] memory initData = new bytes[](1);
    ExtensionOrders memory orders;
    orders.beforeAddLiquidity = 1; // extension index 1, first slot
    orders.beforeRemoveLiquidity = 1;

    PoolParameters memory params = PoolParameters({
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
      adminSpreadFeeE6: 5_000,
      protocolNotionalFeeE8: 0,
      adminNotionalFeeE8: 0,
      adminFeeDestination: makeAddr("adminFeeDest"),
      curBinDistFromProvidedPriceE6: 0,
      nonNegativeBinDataArray: _binData(),
      negativeBinDataArray: _binData(),
      salt: keccak256("MP13-REAL"),
      bidAskRefAsymmetryX8: type(uint16).max
    });

    // (a) factory accepts the real extension ordered under beforeRemoveLiquidity
    address poolAddr = factory.createPool(params);
    assertTrue(factory.isPool(poolAddr), "factory must register the pool");

    // allowlist the LP (pool admin = this test contract)
    ext.setAllowAllDepositors(poolAddr, true);

    vm.startPrank(address(caller));
    token0.approve(poolAddr, type(uint256).max);
    token1.approve(poolAddr, type(uint256).max);
    vm.stopPrank();

    // (b) deposit works
    LiquidityDelta memory deltas = _rangeDeltas(-5, 4, 10_000_000);
    vm.prank(user);
    (uint256 a0, uint256 a1) = caller.addLiquidity(poolAddr, 0, deltas);
    assertGt(a0, 0);
    assertGt(a1, 0);
    console.log("real-ext deposited token0:", a0);
    console.log("real-ext deposited token1:", a1);

    // (c) removal reverts with the real BaseMetricExtension default-hook error
    vm.expectRevert(BaseMetricExtension.ExtensionNotImplemented.selector);
    vm.prank(user);
    caller.removeLiquidity(poolAddr, 0, deltas);

    // permanence: +365 days, still reverts; position intact
    vm.warp(block.timestamp + 365 days);
    vm.expectRevert(BaseMetricExtension.ExtensionNotImplemented.selector);
    vm.prank(user);
    caller.removeLiquidity(poolAddr, 0, deltas);
    assertEq(PoolStateTestLib.positionBinShares(poolAddr, address(caller), 0, -5), 10_000_000);
    assertEq(token0.balanceOf(poolAddr), a0);
    assertEq(token1.balanceOf(poolAddr), a1);
  }
}
