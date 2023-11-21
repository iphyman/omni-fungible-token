// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

contract LzAdapterStorage {
    struct LzState {
        mapping(uint16 => bytes) routers;
        mapping(uint16 => mapping(uint8 => uint256)) gasLookup;
        mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) failedMessages;
    }
}

contract LzAdapterState {
    LzAdapterStorage.LzState _lzState;
}
