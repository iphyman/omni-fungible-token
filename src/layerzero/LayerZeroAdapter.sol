// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import {ILayerZeroEndpoint} from "../interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "../interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroUserApplicationConfig} from "../interfaces/ILayerZeroUserApplicationConfig.sol";
import {LayerZeroAdapterErrorsAndEvents} from "../interfaces/LayerZeroAdapterErrorsAndEvents.sol";

import {BytesLib} from "../libraries/BytesLib.sol";
import {ExcessivelySafeCall} from "../libraries/ExcessivelySafeCall.sol";
import {CommonErrorsAndEvents} from "../interfaces/CommonErrorsAndEvents.sol";

import {Ownable} from "lib/openzeppelin-contracts";
import {LzAdapterState} from "./LzAdapterState.sol";

abstract contract LayerZeroAdapter is
    Ownable,
    LzAdapterState,
    ILayerZeroReceiver,
    CommonErrorsAndEvents,
    LayerZeroAdapterErrorsAndEvents,
    ILayerZeroUserApplicationConfig
{
    using BytesLib for bytes;
    using ExcessivelySafeCall for address;

    ILayerZeroEndpoint public layerZeroEndpoint;

    constructor(address _lzEndpoint) {
        layerZeroEndpoint = ILayerZeroEndpoint(_lzEndpoint);
    }

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external override {
        // Ensures the endpoint caller is layerZero
        _ensureEndpointCaller(address(layerZeroEndpoint));
        // Ensures the message originates from a whitelisted spoke contract
        _ensureTrustedLzRouter(_srcChainId, _srcAddress);

        _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    ///@inheritdoc ILayerZeroUserApplicationConfig
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint256 _configType,
        bytes calldata _config
    ) external override {
        layerZeroEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    ///@inheritdoc ILayerZeroUserApplicationConfig
    function setSendVersion(uint16 _version) external override onlyOwner {
        layerZeroEndpoint.setSendVersion(_version);
    }

    ///@inheritdoc ILayerZeroUserApplicationConfig
    function setReceiveVersion(uint16 _version) external override onlyOwner {
        layerZeroEndpoint.setReceiveVersion(_version);
    }

    ///@inheritdoc ILayerZeroUserApplicationConfig
    function forceResumeReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress
    ) external override onlyOwner {
        layerZeroEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    /**
     * @notice Allows admin/DAO to enable new router chain contract
     * @param _srcChainId layerZero chainId of source
     * @param _srcAdd bytes32 representation of the router address
     * @param _srcAddress contract address of router
     */
    function registerLzRouter(
        uint16 _srcChainId,
        bytes32 _srcAdd,
        bytes memory _srcAddress
    ) external onlyOwner {
        if (_lzState.routers[_srcChainId].length != 0)
            revert RouterAlreadyExists();

        _lzState.routers[_srcChainId] = _srcAddress;

        emit RouterRegistered(_srcChainId, _srcAdd);
    }

    /// @notice Allows operators to set required gas to execute a function
    /// @param _dstChainId layerZero destination chainId
    /// @param _functionType synthmos function type
    /// @param _gas required gas to execute function at destination chain
    function setLzDestGas(
        uint16 _dstChainId,
        uint8 _functionType,
        uint256 _gas
    ) external onlyOwner {
        _lzState.gasLookup[_dstChainId][_functionType] = _gas;
        emit LzGasEstimate(_dstChainId, _functionType, _gas);
    }

    /**
     * @dev Enable messaging routing through layer zero
     * @param _lzEndpoint the layer zero endpoint on this chain
     */
    function enableLayerZero(address _lzEndpoint) external onlyOwner {
        if (address(layerZeroEndpoint) != address(0))
            revert GMPPEnabledAlready();

        layerZeroEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        _lzState.chainId = layerZeroEndpoint.getChainId();
    }

    function nonblockingLzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public {
        _ensureEndpointCaller(address(this));
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    function retryMessage(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public payable {
        bytes32 payloadHash = _lzState.failedMessages[_srcChainId][_srcAddress][
            _nonce
        ];

        if (payloadHash == bytes32(0)) revert NoStoredFailedMessage();
        if (keccak256(_payload) != payloadHash) revert InvalidLzPayload();

        _lzState.failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
    }

    /**
     * @notice Validates if a source is whitelisted
     * @param _srcChainId LayerZero chainId of the source chain
     * @param _srcAddress UA router contract address
     **/
    function _ensureTrustedLzRouter(
        uint16 _srcChainId,
        bytes memory _srcAddress
    ) internal view {
        bytes memory router = _lzState.routers[_srcChainId];

        if (
            router.length == 0 ||
            _srcAddress.length != router.length ||
            keccak256(_srcAddress) != keccak256(router)
        ) {
            revert MisTrustedRouter();
        }
    }

    function _ensureEndpointCaller(address _authorizedCaller) internal view {
        if (_msgSender() != _authorizedCaller) {
            revert UnAuthorizedEndpointCaller();
        }
    }

    /**
     * @notice Internal function to handle received LayerZero message
     * @param _srcChainId the source endpoint identifier
     * @param _srcAddress spoke contract address sending the message
     * @param _nonce the ordered message nonce
     * @param _payload the signed payload is the UA bytes has encoded to be sent
     */
    function _blockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal {
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(
                this.nonblockingLzReceive.selector,
                _srcChainId,
                _srcAddress,
                _nonce,
                _payload
            )
        );

        if (!success) {
            _storeFailedMessage(
                _srcChainId,
                _srcAddress,
                _nonce,
                _payload,
                reason
            );
        }
    }

    function _storeFailedMessage(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload,
        bytes memory _reason
    ) internal {
        _lzState.failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(
            _payload
        );

        emit LzMessageFailed(
            _srcChainId,
            _srcAddress,
            _nonce,
            _payload,
            _reason
        );
    }

    function _lzSend(
        uint16 _dstChainId,
        bytes memory _dstRemote,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams,
        uint256 _nativeFee
    ) internal virtual {
        layerZeroEndpoint.send{value: _nativeFee}(
            _dstChainId,
            _dstRemote,
            _payload,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual;
}
