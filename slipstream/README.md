# Slipstream CL Gauge Parasitic Liquidity PoC

Foundry fork tests demonstrating parasitic liquidity extraction via Slipstream CL gauges on Base. Supplementary material for *Parasitic Liquidity: Emission Extraction via Non-Functional Concentrated Liquidity Positions* (Ryan, 2026).

## Tests

| Test | Property | Description |
|------|----------|-------------|
| `test_Proof1_NoWarmup` | No warmup period | 1-block stake earns non-zero AERO |
| `test_Proof2_WidthIndependence` | Width independence | Single-tick and ten-tick positions earn identical reward per unit liquidity |
| `test_Proof3_DurationIndependence` | Duration independence | Reward rate per second per L is constant regardless of staking duration |

## Contracts Tested

All contracts are unmodified Aerodrome Slipstream mainnet deployments on Base:

| Contract | Address |
|----------|---------|
| CL Pool (VIRTUAL/WETH CL100) | `0x3f0296BF652e19bca772EC3dF08b32732F93014A` |
| CL Gauge | `0x5013Ea8783Bfeaa8c4850a54eacd54D7A3B7f889` |
| NonfungiblePositionManager | `0x827922686190790b37229fd06084350E74485b72` |

## Reproduce

```bash
cd slipstream/
forge install
BASE_RPC_URL=<your_base_rpc_url> forge test -vv
```

Any Base RPC endpoint works (public endpoints, Alchemy, Infura, etc.). Tests fork live mainnet state without pinning a block number; qualitative results (non-zero rewards, equal reward/L ratios) hold deterministically regardless of block.

## Licence

MIT
