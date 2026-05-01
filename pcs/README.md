# PancakeSwap V3 Parasitic Liquidity PoC

Foundry fork tests demonstrating parasitic liquidity extraction via PancakeSwap's MasterChefV3 on two chains: **Base** (has Flashblocks sub-block pre-confirmations) and **BSC** (no Flashblocks, 0.45s native blocks post-Fermi). Supplementary material for *Parasitic Liquidity: Emission Extraction via Non-Functional Concentrated Liquidity Positions* (Ryan, 2026).

## Tests

### Base (PCSParasitic.t.sol)

| Test | Property | Result |
|------|----------|--------|
| `test_PCS_SingleBlockReward` | Non-zero CAKE from 1 block of staking | 2.7e15 CAKE wei in 2 seconds |
| `test_PCS_WidthIndependence` | Reward/liquidity identical for narrow vs wide | 0 bps difference; narrow gets 14x more reward/dollar |
| `test_PCS_DurationIndependence` | No warmup period; constant rate from second 1 | 0 bps difference between 4s and 40s stakes |

### BSC (PCSParasiticBSC.t.sol)

BSC has no Flashblocks or sub-block pre-confirmation layer (Flashblocks is deployed only on OP Stack rollups — Base, Unichain, OP Mainnet). Reproducing the three parasitic properties here demonstrates the vulnerability is chain-architecture-independent and cannot be dismissed as a Base/Flashblocks artefact.

| Test | Property | Result |
|------|----------|--------|
| `test_PCS_BSC_SingleBlockReward` | Non-zero CAKE from 1 second of staking | 2.78e14 CAKE wei in 1 second |
| `test_PCS_BSC_WidthIndependence` | Reward/liquidity identical for narrow vs wide | 0 bps difference; narrow gets 13.7x more reward/dollar |
| `test_PCS_BSC_DurationIndependence` | No warmup period; constant rate from second 1 | 0 bps difference between 2s and 40s stakes (rate = 2.78e14 wei/s in both phases) |

## Contracts Tested

All contracts are unmodified PancakeSwap V3 mainnet deployments.

### Base

| Contract | Address |
|----------|---------|
| MasterChefV3 | `0xC6A2Db661D5a5690172d8eB0a7DEA2d3008665A3` |
| NonfungiblePositionManager | `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364` |
| PancakeV3Factory | `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865` |
| CAKE (Base) | `0x3055913c90Fcc1A6CE9a358911721eEb942013A1` |
| Test Pool (WETH/USDC 500) | `0xB775272E537cc670C65DC852908aD47015244EaF` |

### BSC

| Contract | Address |
|----------|---------|
| MasterChefV3 | `0x556B9306565093C855AEA9AE92A594704c2Cd59e` |
| NonfungiblePositionManager | `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364` |
| Test Pool (WBNB/USDT 500) | `0x36696169C63e42cd08ce11f5deeBbCeBae652050` |

## Reproduce

```bash
# Requires Foundry (https://book.getfoundry.sh)
cd pcs/

# Base tests
BASE_RPC_URL=<your_base_rpc_url> forge test --match-contract PCSParasiticTest -vv

# BSC tests (refutes the "Flashblocks-specific" framing)
BSC_RPC_URL=<your_bsc_rpc_url> forge test --match-contract PCSParasiticBSCTest -vv
```

Public BSC endpoints (e.g. `https://bsc-dataseed.bnbchain.org`) work; Alchemy/QuickNode BSC endpoints work the same.

## Key Findings

1. **Single-block extraction works.** A position staked for one block (2 seconds) receives non-zero CAKE rewards. No minimum staking duration exists.

2. **Width is irrelevant for emission capture.** Reward per unit liquidity is identical regardless of tick range width (0 bps difference). Since narrower ranges produce more liquidity per dollar of capital, a single-tick position earns ~14x more CAKE per dollar than a 20-tick-spacing position.

3. **No warmup period.** The reward rate per second per unit liquidity is identical from the first second of staking. A position staked for 4 seconds earns at the same rate as one staked for 40 seconds (0 bps difference).

These properties enable a parasitic strategy: mint narrow positions, stake for minimal duration, harvest, withdraw, repeat. The operator captures emissions without providing meaningful swap depth.

## Licence

MIT
