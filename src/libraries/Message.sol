// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import { BytesLib } from "./BytesLib.sol";

library Message {
    using BytesLib for bytes;

    /**
     * @notice A list of possible interchain communication channels
     */
    enum Channel {
        AXELAR,
        CHAINLINK_CCIP,
        HYPERLANE,
        LAYERZERO,
        WORMHOLE
    }

    uint8 public constant TRANSFER = 1;
    uint8 public constant TRANSFER_WITH_CALLBACK = 2;

    /// @notice Revert when an invalid payload is provided
    error InvalidPayload();

    function payloadId(bytes memory payload) internal pure returns (uint8) {
        return payload.toUint8(0);
    }

    function remote(bytes memory payload) internal pure returns (bytes32 remoteAddress) {
        remoteAddress = payload.toBytes32(0);
    }

    function encodeTransfer(bytes32 _to, uint64 _amount) internal pure returns (bytes memory payload) {
        payload = abi.encodePacked(TRANSFER, _to, _amount);
    }

    function encodeTransferWithCallback(
        bytes32 _from,
        bytes32 _to,
        uint64 _amount,
        uint64 _gasForCallback,
        bytes memory _payload
    )
        internal
        pure
        returns (bytes memory payload)
    {
        payload = abi.encodePacked(TRANSFER_WITH_CALLBACK, _from, _to, _amount, _gasForCallback, _payload);
    }

    function decodeTransfer(bytes memory payload) internal pure returns (bytes32 to, uint64 amount) {
        uint8 action = payload.toUint8(0);

        if (action != TRANSFER) revert InvalidPayload();

        to = payload.toBytes32(1);
        amount = payload.toUint64(33);
    }

    function decodeTransferWithCallback(bytes memory _payload)
        internal
        pure
        returns (bytes32 from, bytes32 to, uint64 amount, uint64 gasForCallback, bytes memory payload)
    {
        uint8 action = _payload.toUint8(0);

        if (action != TRANSFER_WITH_CALLBACK) revert InvalidPayload();

        from = _payload.toBytes32(1);
        to = _payload.toBytes32(33);
        amount = _payload.toUint64(65);
        gasForCallback = _payload.toUint64(73);
        payload = _payload.slice(81, _payload.length - 81);
    }
}
