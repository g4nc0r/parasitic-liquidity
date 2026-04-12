// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal interface for Slipstream CL Pool
interface ISlipstreamCLPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function tickSpacing() external view returns (int24);
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            bool unlocked
        );
    function rewardGrowthGlobalX128() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function rewardReserve() external view returns (uint256);
    function stakedLiquidity() external view returns (uint128);
}
