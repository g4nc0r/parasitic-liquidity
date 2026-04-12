// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal interface for Slipstream CL Gauge
interface ICLGauge {
    function deposit(uint256 tokenId) external;
    function withdraw(uint256 tokenId) external;
    function getReward(uint256 tokenId) external;
    function earned(address token, uint256 tokenId) external view returns (uint256);
    function rewardToken() external view returns (address);
    function stakingToken() external view returns (address);
}
