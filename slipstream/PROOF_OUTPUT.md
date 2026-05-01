# Slipstream Foundry suite — captured `forge test -vv` output

Regression target for the numerical values cited in *Parasitic Liquidity* §5.1 Table 2 (Slipstream column). The suite is bit-reproducible against any Base archive RPC at the pinned block.

- **Block pin:** Base block 44,140,000 (1 April 2026 18:49 UTC)
- **Pool:** Aerodrome Slipstream VIRTUAL/WETH CL100 at `0x3f0296BF652e19bca772EC3dF08b32732F93014A`
- **Gauge:** `0x5013Ea8783Bfeaa8c4850a54eacd54D7A3B7f889`
- **Reproduce:** `BASE_RPC_URL=<your_base_rpc> forge test -vv`

## Test-to-paper mapping

| Test | Paper claim | Captured value |
|---|---|---|
| `test_Proof1_NoWarmup` | §5.1 Table 2 Slipstream "No warmup" cell: $5.275 \times 10^{14}$ AERO wei after 1 block | `527480800803645` (= $5.275 \times 10^{14}$) |
| `test_Proof2_WidthIndependence` | §5.1 Table 2 Slipstream "Width independence" cell: $7.515 \times 10^{12}$ AERO wei per $L$ | `7514741265961` (= $7.515 \times 10^{12}$) |
| `test_Proof3_DurationIndependence` | §5.1 Table 2 Slipstream "Duration independence" cell: $3.759 \times 10^{11}$ AERO wei per second per $L$ | `375899837951` (= $3.759 \times 10^{11}$) |

## Captured output

```
No files changed, compilation skipped

Ran 3 tests for test/SlipstreamParasitic.t.sol:ParasiticLiquidityTest
[PASS] test_Proof1_NoWarmup() (gas: 830812)
Logs:
  === PROOF 1: No Warmup Period ===
    NFT: 62754485
    Liquidity: 701624139662110941444
    Width: 1 tick spacing
    Duration: 1 block (2s)
    AERO earned: 527480800803645
    [PASS] No warmup -- 1-block stake earned 527480800803645 AERO wei

[PASS] test_Proof2_WidthIndependence() (gas: 1552722)
Logs:
  === PROOF 2: Width Independence ===
    Narrow L: 701624139662110941444
    Wide L:   98850823491766639531
    Narrow rewards: 5272523875513870
    Wide rewards:   742838362467893
    Narrow reward/L: 7514741265961
    Wide reward/L:   7514741265961
    [PASS] Width independence -- reward/L equal within 5%

[PASS] test_Proof3_DurationIndependence() (gas: 1481800)
Logs:
  === PROOF 3: Duration Independence ===
    Short: 4s, rewards: 1054961601607291
    Long: 40s, rewards: 10549616016072916
    Short rate/s/L: 375899837951
    Long rate/s/L:  375899837951
    [PASS] Duration independence -- rate/sec/L constant within 10%

Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 404.22ms (8.99ms CPU time)

Ran 1 test suite in 405.92ms (404.22ms CPU time): 3 tests passed, 0 failed, 0 skipped (3 total tests)
```

Captured 2026-05-01 against `https://mainnet.base.org` (a non-archive endpoint sufficient for this block pin).

## Width-independence capital-efficiency consequence (§5.1 prose)

The narrow position in `test_Proof2_WidthIndependence` produced about $7.1\times$ more liquidity per dollar than the ten-spacing comparator:
- Narrow L = `701624139662110941444` ≈ $7.016 \times 10^{20}$
- Wide L = `98850823491766639531` ≈ $9.885 \times 10^{19}$
- Ratio ≈ 7.10

Combined with width-independent reward/L, this gives the $7.1\times$ AERO-per-dollar capital-efficiency advantage cited in §5.1 prose.

## Re-running

If a re-run produces materially different numbers, either the test was changed or the underlying contracts were redeployed at addresses that differ from those listed above. The pinned block is bit-reproducible against any Base archive RPC; small variations in non-deterministic gas reporting do not affect the captured reward values.
