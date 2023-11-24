// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import { WormholeAdapterErrorsAndEvents } from "../interfaces/WormholeAdapterErrorsAndEvents.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IWormholeRelayer } from "../interfaces/IWormholeRelayer.sol";
import { IWormholeReceiver } from "../interfaces/IWormholeReceiver.sol";
import { CommonErrorsAndEvents } from "../interfaces/CommonErrorsAndEvents.sol";

import { Ownable } from "lib/openzeppelin-contracts";
import { BytesLib } from "../libraries/BytesLib.sol";

abstract contract WormholeAdapter is
    Ownable,
    IWormholeReceiver,
    CommonErrorsAndEvents,
    WormholeAdapterErrorsAndEvents
{
    using BytesLib for bytes;

    struct WormholeState {
        mapping(uint8 => uint256 gasPrice) gasLookup;
        mapping(uint16 => bytes32) routers;
        mapping(bytes32 => bool) consumedMessages;
    }

    IWormhole public wormhole;
    IWormholeRelayer public wormholeRelayer;
    WormholeState public wormholeState;

    modifier onlyWormholeRelayer() {
        if (_msgSender() != address(wormholeRelayer)) {
            revert OnlyWormholeRelayerAllowed();
        }
        _;
    }

    function registerWhRouter(uint16 _srcChainId, bytes32 _srcAddress) external onlyOwner {
        wormholeState.routers[_srcChainId] = _srcAddress;

        emit RouterRegistered(_srcChainId, _srcAddress);
    }

    function receiveWormholeMessages(
        bytes memory _payload,
        bytes[] memory,
        /**
         * additionalVaas
         */
        bytes32 _srcAddress,
        uint16 _srcChainId,
        bytes32 _deliveryHash
    )
        external
        payable
        override
    {
        // Ensure message is comming from a whitelisted router
        if (wormholeState.routers[_srcChainId] != _srcAddress) {
            revert UnAuthorizedWormholeRouter();
        }

        // Ensure the message has not been consumed already
        if (wormholeState.consumedMessages[_deliveryHash]) {
            revert WormholeMessageProcessed();
        }

        wormholeState.consumedMessages[_deliveryHash] = true;

        // call into overriden method
        _wormholeReceive(_payload, _srcAddress, _srcChainId, _deliveryHash);
    }

    function enableWormhole(address _whEndpoint, address _relayer) external onlyOwner {
        if (_whEndpoint == address(0x0)) revert InvalidWormholeEndpoint();
        if (_relayer == address(0x0)) revert InvalidWormholeRelayer();

        wormhole = IWormhole(_whEndpoint);
        wormholeRelayer = IWormholeRelayer(_relayer);
    }

    function _whSend(
        uint16 _dstChainId,
        address _dstAddress,
        address _caller,
        uint256 _gasLimit,
        uint256 _receiveValue,
        bytes memory _payload
    )
        internal
    {
        wormholeRelayer.sendPayloadToEvm{ value: msg.value }(
            _dstChainId, _dstAddress, _payload, _receiveValue, _gasLimit, wormhole.chainId(), _caller
        );
    }

    function _wormholeReceive(
        bytes memory _payload,
        bytes32 _srcAddress,
        uint16 _srcChainId,
        bytes32 _deliveryHash
    )
        internal
        virtual
    { }
}
