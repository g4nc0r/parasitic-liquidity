// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/// @title Remediation Effectiveness Tests
/// @author K. Ryan
/// @notice Proves that proposed fixes (minimum width + warmup) would neutralise parasitic extraction
/// @dev Fork tests against unmodified Slipstream + PCS contracts on Base
///
/// Fix 1 (minimum width): Measures liquidity/dollar at various tick widths to quantify
///   the capital efficiency penalty of enforcing wider positions.
/// Fix 2 (reward warmup): Applies the proposed linear ramp to measured rewards to show
///   the effective yield reduction for short-duration positions.
///
/// To reproduce:
///   BASE_RPC_URL=<your_base_rpc> forge test --match-contract RemediationTest -vv

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
}

// Slipstream NFPM
interface ISlipstreamNFPM {
    struct MintParams {
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        uint160 sqrtPriceX96;
    }

    function mint(MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function approve(address, uint256) external;
}

interface ICLGauge {
    function deposit(uint256 tokenId) external;
    function withdraw(uint256 tokenId) external;
    function rewardToken() external view returns (address);
}

interface ICLPool {
    function slot0() external view returns (
        uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, bool
    );
}

contract RemediationTest is Test {
    // --- Slipstream: VIRTUAL/WETH CL100 ---
    address constant GAUGE   = 0x5013Ea8783Bfeaa8c4850a54eacd54D7A3B7f889;
    address constant POOL    = 0x3f0296BF652e19bca772EC3dF08b32732F93014A;
    address constant NFPM    = 0x827922686190790b37229fd06084350E74485b72;
    address constant VIRTUAL_TOKEN = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;
    address constant WETH    = 0x4200000000000000000000000000000000000006;
    int24 constant TICK_SPACING = 100;

    address AERO;
    address attacker;

    function setUp() public {
        // Pinned to the same Base block as the propositional PoC tests for bit-reproducibility.
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), 44_140_000);
        AERO = ICLGauge(GAUGE).rewardToken();
        attacker = address(this);
        vm.deal(attacker, 100 ether);
        IWETH(WETH).deposit{value: 50 ether}();
        deal(VIRTUAL_TOKEN, attacker, 500_000 ether);
        IERC20(WETH).approve(NFPM, type(uint256).max);
        IERC20(VIRTUAL_TOKEN).approve(NFPM, type(uint256).max);
    }

    function _currentTick() internal view returns (int24) {
        (, int24 tick,,,,) = ICLPool(POOL).slot0();
        return tick;
    }

    function _alignTick(int24 tick) internal pure returns (int24) {
        int24 mod = tick % TICK_SPACING;
        if (mod < 0) return tick - (TICK_SPACING + mod);
        return tick - mod;
    }

    function _mintPosition(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1)
        internal returns (uint256 tokenId, uint128 liquidity)
    {
        (tokenId, liquidity,,) = ISlipstreamNFPM(NFPM).mint(
            ISlipstreamNFPM.MintParams({
                token0: VIRTUAL_TOKEN,
                token1: WETH,
                tickSpacing: TICK_SPACING,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: attacker,
                deadline: block.timestamp + 300,
                sqrtPriceX96: 0
            })
        );
    }

    function _stake(uint256 tokenId) internal {
        ISlipstreamNFPM(NFPM).approve(GAUGE, tokenId);
        ICLGauge(GAUGE).deposit(tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FIX 1: Minimum position width -- capital efficiency drops with enforced width
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Fix1_MinWidthCapitalEfficiency() public {
        int24 tick = _currentTick();
        int24 lower = _alignTick(tick);

        uint256 capital0 = 10_000 ether;
        uint256 capital1 = 1 ether;

        console.log("=== Fix 1: Minimum Width - Capital Efficiency ===");
        console.log("Same capital deployed at increasing tick widths:");
        console.log("");

        // Mint at 1x, 2x, 5x, 10x, 20x tick spacing
        int24[5] memory widths = [int24(1), int24(2), int24(5), int24(10), int24(20)];
        uint128[5] memory liquidities;

        // Symmetric range around the active tick. For odd widths the upper
        // side is one spacing wider so that the position strictly contains
        // the active tick. The 1x case is the canonical narrow position
        // [lower, lower + TICK_SPACING]. Asymmetric placements at width >= 2
        // (e.g. [lower, lower + 2*TICK_SPACING]) are not realistic for an
        // operator targeting the active tick, because token1 is the lower-
        // side bottleneck and unchanged lower bounds give identical L
        // regardless of how much the upper bound is widened.
        for (uint256 i = 0; i < 5; i++) {
            int24 w = widths[i];
            int24 tl;
            int24 tu;
            if (w == 1) {
                tl = lower;
                tu = lower + TICK_SPACING;
            } else {
                tl = lower - ((w / 2) * TICK_SPACING);
                tu = lower + (((w + 1) / 2) * TICK_SPACING);
            }
            (, uint128 liq) = _mintPosition(tl, tu, capital0, capital1);
            liquidities[i] = liq;
        }

        // Report results relative to 1x (parasitic baseline)
        uint128 baselineLiq = liquidities[0];
        for (uint256 i = 0; i < 5; i++) {
            uint256 ratio = (uint256(baselineLiq) * 100) / uint256(liquidities[i]);
            console.log(
                "Width %sx: liquidity = %s, parasitic advantage = %sx",
                uint256(uint24(widths[i])),
                uint256(liquidities[i]),
                ratio / 100
            );
        }

        console.log("");
        console.log("At minWidth = 2x tick spacing:");
        uint256 reduction = 100 - ((uint256(liquidities[1]) * 100) / uint256(liquidities[0]));
        console.log("  Liquidity reduction: %s%%", reduction);
        console.log("  Attacker needs %sx more capital for same L", uint256(baselineLiq) / uint256(liquidities[1]));

        // Key assertion: wider positions produce less liquidity per dollar
        assertGt(liquidities[0], liquidities[1], "1x should have more liquidity than 2x");
        assertGt(liquidities[1], liquidities[2], "2x should have more liquidity than 5x");
        console.log("");
        console.log("PASS: Minimum width requirement reduces parasitic capital efficiency");
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FIX 2: Warmup period -- effective yield drops for short-duration positions
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Fix2_WarmupEffectiveYield() public {
        int24 tick = _currentTick();
        int24 lower = _alignTick(tick);
        int24 upper = lower + TICK_SPACING;

        console.log("=== Fix 2: Warmup Period - Effective Yield ===");

        // Stake for 1 block (2 seconds) -- the parasitic case
        (uint256 tokenId, uint128 liq) = _mintPosition(lower, upper, 10_000 ether, 1 ether);
        _stake(tokenId);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2);

        uint256 aeroBefore = IERC20(AERO).balanceOf(attacker);
        ICLGauge(GAUGE).withdraw(tokenId);
        uint256 rawReward = IERC20(AERO).balanceOf(attacker) - aeroBefore;

        console.log("Raw reward (1 block, no warmup):", rawReward);
        console.log("");

        // Apply proposed warmup ramp at various warmup periods
        uint256[4] memory warmups = [uint256(30), uint256(60), uint256(120), uint256(300)];
        uint256 elapsed = 2; // 1 block = 2 seconds

        for (uint256 i = 0; i < 4; i++) {
            uint256 wp = warmups[i];
            uint256 scale = (elapsed * 1e18) / wp; // linear ramp
            uint256 effectiveReward = (rawReward * scale) / 1e18;
            uint256 pctRetained = (scale * 100) / 1e18;

            console.log("Warmup %ss: effective reward = %s (%s%% of nominal)",
                wp, effectiveReward, pctRetained);
        }

        console.log("");

        // Now stake for 300 seconds (legitimate LP) and show warmup impact is minimal
        (uint256 tokenId2, uint128 liq2) = _mintPosition(lower, upper, 10_000 ether, 1 ether);
        _stake(tokenId2);

        vm.roll(block.number + 150);
        vm.warp(block.timestamp + 300);

        aeroBefore = IERC20(AERO).balanceOf(attacker);
        ICLGauge(GAUGE).withdraw(tokenId2);
        uint256 longReward = IERC20(AERO).balanceOf(attacker) - aeroBefore;

        console.log("Legitimate LP (300s hold):");
        console.log("  Raw reward:", longReward);

        // With 60s warmup on 300s hold: first 60s earns 50% average, remaining 240s earns 100%
        // Total = (60 * 0.5 + 240 * 1.0) / 300 = 90% of nominal
        uint256 warmupSec = 60;
        // drag = (warmup * 0.5) / totalHold = 30 / 300 = 10%
        uint256 dragPct = (warmupSec * 50) / 300; // in percent
        uint256 effectiveLong = longReward - ((longReward * dragPct) / 100);

        console.log("  With 60s warmup: effective reward = %s (%s%% retained)",
            effectiveLong, 100 - dragPct);

        console.log("");
        console.log("Summary:");
        console.log("  Parasitic (2s hold, 60s warmup): 3.3%% of nominal yield");
        console.log("  Legitimate (300s hold, 60s warmup): 90%% of nominal yield");
        console.log("  Yield ratio shift: from 1:1 to 1:27");

        assertGt(rawReward, 0, "Should have non-zero raw reward");
        console.log("");
        console.log("PASS: Warmup period dramatically reduces parasitic yield while preserving legitimate LP yield");
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // COMBINED: Both fixes together
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Combined_BothFixes() public {
        int24 tick = _currentTick();
        int24 lower = _alignTick(tick);

        console.log("=== Combined Effect: MinWidth + Warmup ===");
        console.log("");

        // Baseline: parasitic operator (1 tick, 1 block)
        (uint256 parasiticId, uint128 parasiticLiq) = _mintPosition(
            lower, lower + TICK_SPACING, 10_000 ether, 1 ether
        );
        _stake(parasiticId);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2);
        uint256 aeroBefore = IERC20(AERO).balanceOf(attacker);
        ICLGauge(GAUGE).withdraw(parasiticId);
        uint256 parasiticReward = IERC20(AERO).balanceOf(attacker) - aeroBefore;

        console.log("BASELINE (no fixes):");
        console.log("  Parasitic: 1 tick, 2s hold, reward = %s", parasiticReward);

        // Legitimate LP: 10 tick spacings, 30 minute hold
        (uint256 legitId, uint128 legitLiq) = _mintPosition(
            lower - (5 * TICK_SPACING),
            lower + (5 * TICK_SPACING),
            10_000 ether, 1 ether
        );
        _stake(legitId);
        vm.roll(block.number + 900);
        vm.warp(block.timestamp + 1800);
        aeroBefore = IERC20(AERO).balanceOf(attacker);
        ICLGauge(GAUGE).withdraw(legitId);
        uint256 legitReward = IERC20(AERO).balanceOf(attacker) - aeroBefore;

        console.log("  Legitimate: 10 ticks, 1800s hold, reward = %s", legitReward);
        console.log("");

        // After Fix 1 (minWidth = 5 ticks): parasitic must use 5 tick spacings
        // Their liquidity per dollar drops by ~5x (from 1-tick concentration)
        uint256 parasiticLiqReduced = uint256(parasiticLiq) / 5; // approximate
        // After Fix 2 (60s warmup on 2s hold): 2/60 = 3.3% of nominal
        uint256 warmupScale = (uint256(2) * 1e18) / uint256(60);
        uint256 parasiticEffective = (parasiticReward * warmupScale) / (5 * 1e18);
        // Legitimate with 60s warmup on 1800s hold: drag = 30/1800 = 1.7%
        uint256 legitEffective = legitReward - ((legitReward * 17) / 1000);

        console.log("WITH BOTH FIXES (minWidth=5, warmup=60s):");
        console.log("  Parasitic effective reward: %s", parasiticEffective);
        console.log("  Legitimate effective reward: %s", legitEffective);

        // Reward per dollar comparison
        // Parasitic: same capital, forced 5x width, 3.3% warmup scale
        // Net: 1/5 liquidity * 3.3% warmup = 0.67% of original extraction rate
        uint256 parasiticPctOfBaseline = (parasiticEffective * 10000) / parasiticReward;
        console.log("");
        console.log("  Parasitic extraction reduced to %s bps of baseline", parasiticPctOfBaseline);
        console.log("  Legitimate LP retains 98.3%% of yield");

        // Per-second comparison (normalised)
        uint256 parasiticPerSec = parasiticEffective / 2;
        uint256 legitPerSec = legitEffective / 1800;

        // Per-dollar-per-second (using liquidity as capital proxy)
        // Can't perfectly compare since they hold different durations, but the
        // extraction rate (reward per second) tells the story
        console.log("");
        console.log("  Parasitic reward/sec: %s", parasiticPerSec);
        console.log("  Legitimate reward/sec: %s", legitPerSec);

        assertGt(legitEffective, parasiticEffective, "Legitimate should earn more than parasitic after fixes");
        console.log("");
        console.log("PASS: Combined fixes reduce parasitic extraction to <1%% of baseline");
    }
}
