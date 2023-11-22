// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

contract LzAdapterStorage {
    struct LzState {
        uint16 chainId;
        mapping(uint16 => bytes) routers;
        mapping(uint16 => mapping(uint8 => uint256)) gasLookup;
        mapping(uint16 => mapping(bytes => mapping(uint64 => bool))) minted;
        mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) failedMessages;
    }
}

contract LzAdapterState {
    LzAdapterStorage.LzState _lzState;
}
