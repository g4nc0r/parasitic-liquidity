// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal ERC20 interface
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}
