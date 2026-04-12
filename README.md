# Parasitic Liquidity

Code, fork tests, and supplementary data for:

> Ryan, K.R. (2026). *Parasitic Liquidity: Emission Extraction via Non-Functional Concentrated Liquidity Positions.* SSRN 6510118.

**Paper:** [`parasitic-liquidity.pdf`](./parasitic-liquidity.pdf) | [SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6510118)

## Overview

This paper demonstrates that concentrated liquidity (CL) gauges in ve(3,3) DEXes (including Aerodrome Slipstream and PancakeSwap V3) distribute emissions proportionally to staked liquidity without accounting for position width, stake duration, or liquidity utilisation. Rational actors exploit this by deploying minimal-width, single-block positions that extract disproportionate rewards while providing negligible trading depth.

## Fork Tests

All tests run against **live Base mainnet state** via Foundry fork mode. No mocks. All tests prove the vulnerability on deployed, unmodified contracts.

### Slipstream (Aerodrome on Base)

```bash
cd slipstream/
forge install
BASE_RPC_URL=<your_base_rpc_url> forge test -vv
```

| Test | Property Proven |
|------|-----------------|
| `test_Proof1_NoWarmup` | 1-block stake earns non-zero AERO |
| `test_Proof2_WidthIndependence` | Single-tick and ten-tick positions earn identical reward per unit liquidity |
| `test_Proof3_DurationIndependence` | Reward rate per second per L is constant regardless of duration |

### PancakeSwap V3 (on Base)

```bash
cd pcs/
forge install
BASE_RPC_URL=<your_base_rpc_url> forge test -vv
```

| Test | Property Proven |
|------|-----------------|
| `test_PCS_SingleBlockReward` | Non-zero CAKE from 1 block of staking |
| `test_PCS_WidthIndependence` | Reward/liquidity identical for narrow vs wide (0 bps difference) |
| `test_PCS_DurationIndependence` | No warmup period; constant rate from second 1 |

### Remediation Validation

`pcs/test/RemediationTest.t.sol` validates the proposed fix mechanism (minimum stake time + width-weighted rewards).

## Supplementary Materials

| File | Description |
|------|-------------|
| `parasitic-liquidity.pdf` | Published paper |
| `parasitic-liquidity.tex` | LaTeX source |

## Layout

```
parasitic-liquidity/
├── parasitic-liquidity.pdf / .tex
├── slipstream/              ← Aerodrome fork tests
│   ├── src/                   Interface shims (ICLGauge, INPM, etc.)
│   ├── test/                  SlipstreamParasitic.t.sol (3 tests)
│   ├── foundry.toml / .lock
│   └── README.md
└── pcs/                     ← PancakeSwap V3 fork tests
    ├── test/                  PCSParasitic + RemediationTest + HelperLib
    ├── FINDINGS.md
    ├── foundry.toml / .lock
    └── README.md
```

## Reproducing

Requires [Foundry](https://book.getfoundry.sh/) and a Base RPC endpoint (e.g. Alchemy, Infura).

Fork tests run against live mainnet state. Tests do not pin a block number; qualitative results (non-zero rewards, equal reward/L ratios) hold deterministically regardless of block.

## Citing

```bibtex
@techreport{ryan2026parasitic,
  author      = {Ryan, K.R.},
  title       = {Parasitic Liquidity: Emission Extraction via Non-Functional Concentrated Liquidity Positions},
  institution = {SSRN},
  number      = {6510118},
  year        = {2026}
}
```

## Licence

Code: MIT. Paper: © the author, all rights reserved (canonical at SSRN).
