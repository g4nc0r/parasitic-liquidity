// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ISlipstreamCLPool} from "../src/ISlipstreamCLPool.sol";
import {INonfungiblePositionManager} from "../src/INonfungiblePositionManager.sol";
import {ICLGauge} from "../src/ICLGauge.sol";
import {IERC20} from "../src/IERC20.sol";

/**
 * @title ParasiticLiquidity -- Formal Proof-of-Concept
 * @notice Proves Slipstream CL gauges reward instantaneous staked liquidity
 *         with no warmup, no minimum width, and no utilisation check.
 * @dev    Forks Base mainnet. Tests against unmodified production contracts.
 *
 *         Proof 1: NO WARMUP -- 1-block stake earns non-zero AERO.
 *         Proof 2: WIDTH INDEPENDENCE -- reward/L is equal for narrow and wide.
 *         Proof 3: DURATION INDEPENDENCE -- reward rate per second is constant.
 */
contract ParasiticLiquidityTest is Test {
    address constant VIRTUAL = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;
    address constant WETH    = 0x4200000000000000000000000000000000000006;
    address constant POOL    = 0x3f0296BF652e19bca772EC3dF08b32732F93014A; // VIRTUAL/WETH CL100
    address constant NFPM    = 0x827922686190790b37229fd06084350E74485b72;
    address constant GAUGE   = 0x5013Ea8783Bfeaa8c4850a54eacd54D7A3B7f889;
    address constant AERO    = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant TOKEN0  = VIRTUAL;
    address constant TOKEN1  = WETH;
    int24 constant TS = 100;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    ISlipstreamCLPool pool;
    INonfungiblePositionManager nfpm;
    ICLGauge gauge;
    int24 tick;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), 44_140_000);
        pool  = ISlipstreamCLPool(POOL);
        nfpm  = INonfungiblePositionManager(NFPM);
        gauge = ICLGauge(GAUGE);
        (,tick,,,,) = pool.slot0();
        require(pool.rewardRate() > 0, "Gauge must have active emissions");
        _fund(alice);
        _fund(bob);
    }

    /// @notice Proof 1: A position staked for 1 block earns non-zero rewards.
    function test_Proof1_NoWarmup() public {
        console2.log("=== PROOF 1: No Warmup Period ===");

        int24 lo = _align(tick);
        int24 hi = lo + TS;

        (uint256 id, uint128 liq) = _mint(alice, lo, hi);
        console2.log("  NFT:", id);
        console2.log("  Liquidity:", uint256(liq));
        console2.log("  Width: 1 tick spacing");

        vm.prank(alice);
        nfpm.approve(GAUGE, id);
        vm.prank(alice);
        gauge.deposit(id);

        // Advance 1 block
        vm.warp(block.timestamp + 2);
        vm.roll(block.number + 1);

        // Collect rewards via balance diff
        uint256 before = IERC20(AERO).balanceOf(alice);
        vm.prank(alice);
        gauge.getReward(id);
        uint256 rewards = IERC20(AERO).balanceOf(alice) - before;

        vm.prank(alice);
        gauge.withdraw(id);

        console2.log("  Duration: 1 block (2s)");
        console2.log("  AERO earned:", rewards);

        assertTrue(rewards > 0, "PROOF 1 FAILED: 1-block stake must earn non-zero rewards");
        console2.log("  [PASS] No warmup -- 1-block stake earned", rewards, "AERO wei");
    }

    /// @notice Proof 2: Reward per unit L is equal for narrow and wide positions.
    function test_Proof2_WidthIndependence() public {
        console2.log("=== PROOF 2: Width Independence ===");

        int24 nLo = _align(tick);
        int24 nHi = nLo + TS;
        int24 wLo = _align(tick - 500);
        int24 wHi = _align(tick + 500);

        (uint256 nId, uint128 nL) = _mint(alice, nLo, nHi);
        (uint256 wId, uint128 wL) = _mint(bob, wLo, wHi);

        console2.log("  Narrow L:", uint256(nL));
        console2.log("  Wide L:  ", uint256(wL));

        // Deposit both
        vm.prank(alice); nfpm.approve(GAUGE, nId);
        vm.prank(alice); gauge.deposit(nId);
        vm.prank(bob);   nfpm.approve(GAUGE, wId);
        vm.prank(bob);   gauge.deposit(wId);

        // Advance 10 blocks
        vm.warp(block.timestamp + 20);
        vm.roll(block.number + 10);

        // Collect narrow
        uint256 b1 = IERC20(AERO).balanceOf(alice);
        vm.prank(alice); gauge.getReward(nId);
        uint256 nR = IERC20(AERO).balanceOf(alice) - b1;

        // Collect wide
        uint256 b2 = IERC20(AERO).balanceOf(bob);
        vm.prank(bob); gauge.getReward(wId);
        uint256 wR = IERC20(AERO).balanceOf(bob) - b2;

        console2.log("  Narrow rewards:", nR);
        console2.log("  Wide rewards:  ", wR);

        uint256 nRPL = nR * 1e18 / uint256(nL);
        uint256 wRPL = wR * 1e18 / uint256(wL);
        console2.log("  Narrow reward/L:", nRPL);
        console2.log("  Wide reward/L:  ", wRPL);

        // Clean up
        vm.prank(alice); gauge.withdraw(nId);
        vm.prank(bob);   gauge.withdraw(wId);

        uint256 diff = nRPL > wRPL ? nRPL - wRPL : wRPL - nRPL;
        uint256 max  = nRPL > wRPL ? nRPL : wRPL;
        uint256 tol  = max * 5 / 100;

        assertLe(diff, tol, "PROOF 2 FAILED: reward/L must be equal regardless of width");
        console2.log("  [PASS] Width independence -- reward/L equal within 5%");
    }

    /// @notice Proof 3: Reward rate per second per L is constant.
    function test_Proof3_DurationIndependence() public {
        console2.log("=== PROOF 3: Duration Independence ===");

        int24 lo = _align(tick);
        int24 hi = lo + TS;

        // Alice: short (4 seconds)
        (uint256 sId, uint128 sL) = _mint(alice, lo, hi);
        vm.prank(alice); nfpm.approve(GAUGE, sId);
        vm.prank(alice); gauge.deposit(sId);

        vm.warp(block.timestamp + 4);
        vm.roll(block.number + 2);

        uint256 b1 = IERC20(AERO).balanceOf(alice);
        vm.prank(alice); gauge.getReward(sId);
        uint256 sR = IERC20(AERO).balanceOf(alice) - b1;
        vm.prank(alice); gauge.withdraw(sId);

        // Bob: long (40 seconds)
        (uint256 lId, uint128 lL) = _mint(bob, lo, hi);
        vm.prank(bob); nfpm.approve(GAUGE, lId);
        vm.prank(bob); gauge.deposit(lId);

        vm.warp(block.timestamp + 40);
        vm.roll(block.number + 20);

        uint256 b2 = IERC20(AERO).balanceOf(bob);
        vm.prank(bob); gauge.getReward(lId);
        uint256 lR = IERC20(AERO).balanceOf(bob) - b2;
        vm.prank(bob); gauge.withdraw(lId);

        console2.log("  Short: 4s, rewards:", sR);
        console2.log("  Long: 40s, rewards:", lR);

        uint256 sRate = sR * 1e18 / (4 * uint256(sL));
        uint256 lRate = lR * 1e18 / (40 * uint256(lL));
        console2.log("  Short rate/s/L:", sRate);
        console2.log("  Long rate/s/L: ", lRate);

        uint256 diff = sRate > lRate ? sRate - lRate : lRate - sRate;
        uint256 max  = sRate > lRate ? sRate : lRate;
        uint256 tol  = max * 10 / 100;

        assertLe(diff, tol, "PROOF 3 FAILED: rate/sec/L must be constant");
        console2.log("  [PASS] Duration independence -- rate/sec/L constant within 10%");
    }

    // ===== Helpers =====

    function _fund(address who) internal {
        deal(WETH, who, 5 ether);
        deal(VIRTUAL, who, 50_000 ether);
    }

    function _align(int24 t) internal pure returns (int24) {
        int24 r = t % TS;
        if (r < 0) return t - r - TS;
        return t - r;
    }

    function _mint(address who, int24 lo, int24 hi) internal returns (uint256 id, uint128 liq) {
        vm.startPrank(who);
        IERC20(TOKEN0).approve(NFPM, type(uint256).max);
        IERC20(TOKEN1).approve(NFPM, type(uint256).max);
        (id, liq,,) = nfpm.mint(
            INonfungiblePositionManager.MintParams({
                token0: TOKEN0,
                token1: TOKEN1,
                tickSpacing: TS,
                tickLower: lo,
                tickUpper: hi,
                amount0Desired: 500 ether,
                amount1Desired: 0.05 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: who,
                deadline: block.timestamp + 60,
                sqrtPriceX96: 0
            })
        );
        vm.stopPrank();
    }
}
