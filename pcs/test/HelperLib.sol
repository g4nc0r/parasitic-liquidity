// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library PoolHelper {
    function getSlot0(address pool) internal view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex
    ) {
        (bool success, bytes memory data) = pool.staticcall(
            abi.encodeWithSignature("slot0()")
        );
        require(success, "slot0 failed");
        
        // Manually extract fields to avoid Solidity tuple unpacking bug
        assembly {
            sqrtPriceX96 := mload(add(data, 32))
            tick := mload(add(data, 64))
            observationIndex := mload(add(data, 96))
        }
    }
    
    function getTickSpacing(address pool) internal view returns (int24) {
        (bool success, bytes memory data) = pool.staticcall(
            abi.encodeWithSignature("tickSpacing()")
        );
        require(success, "tickSpacing failed");
        
        return abi.decode(data, (int24));
    }
    
    function getToken0(address pool) internal view returns (address) {
        (bool success, bytes memory data) = pool.staticcall(
            abi.encodeWithSignature("token0()")
        );
        require(success, "token0 failed");
        return abi.decode(data, (address));
    }
    
    function getToken1(address pool) internal view returns (address) {
        (bool success, bytes memory data) = pool.staticcall(
            abi.encodeWithSignature("token1()")
        );
        require(success, "token1 failed");
        return abi.decode(data, (address));
    }
    
    function getFee(address pool) internal view returns (uint24) {
        (bool success, bytes memory data) = pool.staticcall(
            abi.encodeWithSignature("fee()")
        );
        require(success, "fee failed");
        return abi.decode(data, (uint24));
    }
}
