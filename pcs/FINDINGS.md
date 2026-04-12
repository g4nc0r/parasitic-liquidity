# PancakeSwap V3 MasterChefV3: Parasitic Liquidity Findings

## Summary

All three tests pass with live CAKE emissions. PancakeSwap's MasterChefV3 on Base is confirmed vulnerable to parasitic liquidity attacks structurally identical to those demonstrated against Slipstream CL gauges.

## Test Results

```
Ran 3 tests for test/PCSParasitic.t.sol:PCSParasiticTest
[PASS] test_PCS_SingleBlockReward()
[PASS] test_PCS_WidthIndependence()
[PASS] test_PCS_DurationIndependence()

Suite result: ok. 3 passed; 0 failed; 0 skipped
```

## Key Findings

### Test 1: Single Block Reward

A position staked for one block (2 seconds) receives non-zero CAKE rewards. No warmup period exists.

### Test 2: Width Independence

Narrow (1 tick spacing) and wide (20 tick spacings) positions receive identical reward per unit liquidity (0 basis points difference). The narrow position produces approximately 14--19x more liquidity per dollar of capital, and therefore earns 14--19x more CAKE per dollar deployed.

### Test 3: Duration Independence

Reward rate per second per unit of liquidity is identical for a 4-second stake and a 40-second stake (0 basis points difference). No warmup curve.

## Cross-Protocol Comparison

| Property | Aerodrome Slipstream | PancakeSwap V3 |
|----------|---------------------|----------------|
| Reward formula | L x time_in_range | L x time_in_range |
| Width normalisation | None | None |
| Warmup period | None | None |
| Lockup requirement | None | None |

Both implementations inherit the Synthetix reward accumulator pattern and apply it unchanged to non-fungible concentrated liquidity positions.

## Reproduction

```bash
cd pcs/
forge install
BASE_RPC_URL=<your_base_rpc_url> forge test -vv
```
