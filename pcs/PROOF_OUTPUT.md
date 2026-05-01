# PancakeSwap V3 Foundry suite — captured `forge test -vv` output

Regression target for the numerical values cited in *Parasitic Liquidity* §5.1 Table 2 (PancakeSwap column) and §6 (remediation analysis).

## Test contracts and pinning

| Contract | Chain | Pin | Pool |
|---|---|---|---|
| `PCSParasitic.t.sol` | Base | block 44,140,000 (1 April 2026 18:49 UTC) | WETH/USDC 500-bps via `MasterChefV3` |
| `PCSParasiticBSC.t.sol` | BSC | block 86,732,564 (15 March 2026 12:00 UTC) | USDT/WBNB 0.01% via `MasterChefV3` |
| `RemediationTest.t.sol` | Base | block 44,140,000 | Aerodrome Slipstream VIRTUAL/WETH CL100 (NFPM mints; reward analysis off-chain scaling) |

All three pinned blocks are bit-reproducible against any archive RPC. Reproduce with `BASE_RPC_URL=<your_base_rpc> BSC_RPC_URL=<your_bsc_rpc> forge test -vv` from the `pcs/` directory.

## Test-to-paper mapping

### PCS Base proposition tests

| Test | Paper claim | Captured value |
|---|---|---|
| `test_PCS_SingleBlockReward` | §5.1 Table 2 PancakeSwap "No warmup" cell: $2.915 \times 10^{15}$ CAKE wei after 1 block | `2914620654407929` (= $2.915 \times 10^{15}$) |
| `test_PCS_WidthIndependence` | §5.1 Table 2 PancakeSwap "Width independence" cell: $9.767 \times 10^{17}$ CAKE wei per $L$ | `976732096420396908` (= $9.767 \times 10^{17}$) |
| `test_PCS_DurationIndependence` | §5.1 Table 2 PancakeSwap "Duration independence" cell: $1.457 \times 10^{15}$ CAKE wei per second per $L$ | `1457310327203964` (= $1.457 \times 10^{15}$) |

Width-independence capital-efficiency consequence: the narrow position produced about $11\times$ more liquidity per dollar than the twenty-tick comparator, matching the §5.1 prose.

### PCS BSC reproduction

| Test | Property |
|---|---|
| `test_PCS_BSC_SingleBlockReward` | Non-zero CAKE from a single second of staking on BSC at block 86,732,564 (rate `1132845405819793` wei/sec) |
| `test_PCS_BSC_WidthIndependence` | Reward per unit liquidity identical for narrow vs wide (0 bps difference; reward/$L$ = 381,724,882,370 ×1e18 in both cases) |
| `test_PCS_BSC_DurationIndependence` | No warmup; rate constant from second 1 (0 bps difference between 2-second and 40-second stakes) |

The BSC reproduction demonstrates the vulnerability is chain-architecture-independent and not a Base/Flashblocks artefact. The numerical CAKE-per-second rate is BSC-pool-specific and not cited in the paper's Table 2; the qualitative pass/fail is what matters.

### Remediation tests (§6)

| Test | Paper claim | Captured |
|---|---|---|
| `test_Combined_BothFixes` | §6.3 Table 4: combined fix reduces parasitic to 0.66% of baseline | "Parasitic extraction reduced to 66 bps of baseline" |
| `test_Fix1_MinWidthCapitalEfficiency` | §6.2: enforcing $5\times$ tick spacing requires $\sim 3\times$ more capital, $10\times$ requires $7\times$, $20\times$ requires $13\times$ | width 5x → 3x, width 10x → 7x, width 20x → 13x |
| `test_Fix2_WarmupEffectiveYield` | §6.3: warmup alone shifts the parasitic/legitimate yield ratio from 1:1 to 1:27 | confirmed: parasitic 3.3% of nominal, legitimate 90% retained |

## Captured output

### `PCSParasitic.t.sol` (Base, pinned 44,140,000)

```
No files changed, compilation skipped

Ran 3 tests for test/PCSParasitic.t.sol:PCSParasiticTest
[PASS] test_PCS_DurationIndependence() (gas: 1198956)
Logs:
  --- Test 3: Duration Independence ---
  Phase A: 4 seconds
    CAKE reward: 5829241308815858
    Rate/sec:    1457310327203964
  Phase B: 40 seconds
    CAKE reward: 58292413088158586
    Rate/sec:    1457310327203964
  Rate difference (bps): 0
  PASS: No warmup period - reward rate is constant from first second

[PASS] test_PCS_SingleBlockReward() (gas: 757958)
Logs:
  --- Test 1: Single Block Reward ---
  Liquidity: 88044113279118611
  CAKE earned (1 block / 2s): 2914620654407929
  PASS: Non-zero reward from single block of staking

[PASS] test_PCS_WidthIndependence() (gas: 1368079)
Logs:
  --- Test 2: Width Independence ---
  Narrow liquidity: 88044113279118611
  Wide liquidity:   7911724543925837
  Liquidity ratio (narrow/wide): 11
  Narrow CAKE reward: 85995511340588427
  Wide CAKE reward:   7727635300089391
  Narrow reward/liquidity (x1e18): 976732096420396908
  Wide reward/liquidity (x1e18):   976732096420396860
  Difference (bps): 0
  Narrow gets 11x more reward per dollar deployed
  PASS: Reward per unit liquidity is width-independent

Suite result: ok. 3 passed; 0 failed; 0 skipped
```

### `PCSParasiticBSC.t.sol` (BSC, pinned 86,732,564)

```
Ran 3 tests for test/PCSParasiticBSC.t.sol:PCSParasiticBSCTest
[PASS] test_PCS_BSC_DurationIndependence() (gas: 1260819)
Logs:
  --- Test 3 (BSC): Duration Independence ---
  Phase A: 2 seconds
    CAKE reward: 2265690811639587
    Rate/sec:    1132845405819793
  Phase B: 40 seconds
    CAKE reward: 45313816232791755
    Rate/sec:    1132845405819793
  Rate difference (bps): 0
  PASS: No warmup period on BSC - reward rate constant from first second

[PASS] test_PCS_BSC_SingleBlockReward() (gas: 824456)
Logs:
  --- Test 1 (BSC): Single Block Reward ---
  Liquidity: 171700860847022818159080
  CAKE earned (1 second): 1132845405819793
  PASS: Non-zero reward from single-second staking on BSC (no Flashblocks)

[PASS] test_PCS_BSC_WidthIndependence() (gas: 1425619)
Logs:
  --- Test 2 (BSC): Width Independence ---
  Narrow liquidity: 171700860847022818159080
  Wide liquidity:   15327996923347210899046
  Narrow CAKE reward: 65542490909753604
  Wide CAKE reward:   5851077822541013
  Narrow reward/liquidity (x1e18): 381724882370
  Wide reward/liquidity (x1e18):   381724882370
  Difference (bps): 0
  PASS: Reward per unit liquidity is width-independent on BSC

Suite result: ok. 3 passed; 0 failed; 0 skipped
```

### `RemediationTest.t.sol` (Base, pinned 44,140,000)

```
Ran 3 tests for test/RemediationTest.t.sol:RemediationTest
[PASS] test_Combined_BothFixes() (gas: 1421002)
Logs:
  === Combined Effect: MinWidth + Warmup ===
  BASELINE (no fixes):
    Parasitic: 1 tick, 2s hold, reward = 9967300798821746
    Legitimate: 10 ticks, 1800s hold, reward = 1330252973012904439
  WITH BOTH FIXES (minWidth=5, warmup=60s):
    Parasitic effective reward: 66448671992144
    Legitimate effective reward: 1307638672471685064
  Parasitic extraction reduced to 66 bps of baseline
  Legitimate LP retains 98.3% of yield
  PASS: Combined fixes reduce parasitic extraction to <1% of baseline

[PASS] test_Fix1_MinWidthCapitalEfficiency() (gas: 1610437)
Logs:
  === Fix 1: Minimum Width - Capital Efficiency ===
  Width 1x:  liquidity = 14032482793242218828886, parasitic advantage = 1x
  Width 2x:  liquidity =  6287554856592394774967, parasitic advantage = 2x
  Width 5x:  liquidity =  4058644799505007684974, parasitic advantage = 3x
  Width 10x: liquidity =  1977016469835332790625, parasitic advantage = 7x
  Width 20x: liquidity =  1075692616998114663408, parasitic advantage = 13x
  At minWidth = 2x tick spacing: liquidity reduction 56%, attacker needs 2x more capital for same L
  PASS: Minimum width requirement reduces parasitic capital efficiency

[PASS] test_Fix2_WarmupEffectiveYield() (gas: 1348743)
Logs:
  === Fix 2: Warmup Period - Effective Yield ===
  Raw reward (1 block, no warmup): 9967300798821746
  Warmup 30s:  effective reward = 664486719921449  (6% of nominal)
  Warmup 60s:  effective reward = 332243359960724  (3% of nominal)
  Warmup 120s: effective reward = 166121679980362  (1% of nominal)
  Warmup 300s: effective reward = 66448671992144   (0% of nominal)
  Legitimate (300s hold) with 60s warmup: 90% retained
  Yield ratio shift: from 1:1 to 1:27
  PASS: Warmup period dramatically reduces parasitic yield while preserving legitimate LP yield
```

Captured 2026-05-01.

## Re-running

A fresh run at the same pinned blocks should produce bit-identical CAKE wei values (the values above) on every test. If a re-run produces materially different numbers, either the test was changed, the underlying contracts were redeployed, or the RPC's archive node is serving a different chain state than mainnet. The pinned blocks are independent of the RPC provider; any archive node serving mainnet at those heights returns the same state.
