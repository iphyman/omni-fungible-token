// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

interface LayerZeroAdapterErrorsAndEvents {
    ///@notice Emitted when
    event LzMessageFailed(
        uint16 _srcChainId,
        bytes _srcAddress,
        uint64 _nonce,
        bytes _payload,
        bytes _reason
    );

    ///@notice Emitted when
    event RetryMessageSuccess(
        uint16 _srcChainId,
        bytes _srcAddress,
        uint64 _nonce,
        bytes32 _payloadHash
    );

    ///@notice Emitted when estimated gasprice is set for a remote function call
    event LzGasEstimate(uint16 _dstChainId, uint8 _functionType, uint256 _gas);

    ///@notice Revert when trying to retry a
    error UnAuthorizedLzCall();

    ///@notice
    error NoStoredFailedMessage();

    ///@notice Thrown the payload size exceeds max
    error InvalidLzPayload();

    /// @notice Thrown when lzReceive is not called by the lzEndpoint
    error UnAuthorizedEndpointCaller();
}
