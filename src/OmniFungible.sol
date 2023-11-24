// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import { IOmniFungible } from "./interfaces/IOmniFungible.sol";
import { IReceiveTransferCallback } from "./interfaces/IReceiveTransferCallback.sol";

import { AddressTypeCast } from "./libraries/AddressTypeCast.sol";
import { Message } from "./libraries/Message.sol";
import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { ExcessivelySafeCall } from "./libraries/ExcessivelySafeCall.sol";

import { LayerZeroAdapter } from "./adapters/LayerZeroAdapter.sol";
import { WormholeAdapter } from "./adapters/WormholeAdapter.sol";

contract OmniFungible is IOmniFungible, Ownable, ERC20, WormholeAdapter, LayerZeroAdapter {
    using Message for bytes;
    using AddressTypeCast for bytes32;
    using AddressTypeCast for address;
    using ExcessivelySafeCall for address;

    uint256 constant DEFAULT_GAS_LIMIT = 500_000;

    constructor(string memory _name, string memory _symbol) Ownable() ERC20(_name, _symbol) { }

    /// @inheritdoc IOmniFungible
    function transferFrom(
        uint16 dstChainId,
        address from,
        bytes32 to,
        uint256 value,
        AdapterCallParams calldata params
    )
        external
        payable
        override
    {
        _remoteTransfer(dstChainId, from, to, value, params);
    }

    /// @inheritdoc IOmniFungible
    function transferFromWithCallback(
        uint16 dstChainId,
        address from,
        bytes32 to,
        uint256 value,
        uint64 gasForCallback,
        bytes calldata payload,
        AdapterCallParams calldata params
    )
        external
        payable
        override
    {
        _remoteTransferWithCallback(dstChainId, from, to, value, gasForCallback, payload, params);
    }

    /// @inheritdoc IOmniFungible
    function circulatingSupply() external view override returns (uint256) {
        return totalSupply();
    }

    function _normalizeAmount(uint256 _amount) internal view returns (uint64) {
        uint8 _decimals = decimals();

        if (_decimals > 8) {
            _amount /= 10 ** (_decimals - 8);
        }

        return uint64(_amount);
    }

    function _deNormalizeAmount(uint64 _amount) internal view returns (uint256 amount) {
        amount = uint256(_amount);
        uint8 _decimals = decimals();

        if (_decimals > 8) {
            amount *= 10 ** (_decimals - 8);
        }

        return amount;
    }

    function _transferFrom(address _from, address _to, uint256 _amount) internal {
        address spender = _msgSender();

        if (_from != address(this) && _from != spender) {
            _spendAllowance(_from, spender, _amount);
        }

        _transfer(_from, _to, _amount);
    }

    function tryCallback(
        uint16 srcChainId,
        bytes calldata srcAddress,
        uint64,
        /**
         * nonce
         */
        bytes32 from,
        address to,
        uint256 amount,
        uint256 gasForCall,
        bytes calldata payload
    )
        public
    {
        if (_msgSender() != address(this)) revert NotOminiFungible();

        _transferFrom(address(this), to, amount);
        emit RemoteTransferReceived(srcChainId, to, amount);

        IReceiveTransferCallback(to).onReceiveTransfer{ gas: gasForCall }(srcChainId, srcAddress, from, amount, payload);
    }

    function _remoteTransfer(
        uint16 dstChainId,
        address from,
        bytes32 to,
        uint256 value,
        AdapterCallParams memory params
    )
        internal
    {
        uint64 normalizedAmount = _normalizeAmount(value);
        bytes memory payload = Message.encodeTransfer(to, normalizedAmount);

        address spender = _msgSender();
        Message.Channel channel = Message.Channel(params.adapter);

        if (from != spender) _spendAllowance(from, spender, value);

        _burn(from, value);

        if (channel == Message.Channel.LAYERZERO) {
            bytes memory remoteRouter = lzState.routers[dstChainId];
            bytes memory adapterParams = _lzAdapterParam(DEFAULT_GAS_LIMIT);
            //TODO: ensure remoteRouter is valid
            _lzSend(dstChainId, remoteRouter, payload, params.refundAddress, address(0), adapterParams, msg.value);
        } else if (channel == Message.Channel.WORMHOLE) {
            address remoteRouter = AddressTypeCast.bytes32ToAddress(wormholeState.routers[dstChainId]);
            _whSend(dstChainId, remoteRouter, _msgSender(), DEFAULT_GAS_LIMIT, 0, payload);
        } else {
            revert UnsupportedAction();
        }

        emit RemoteTransfer(dstChainId, to, from, value);
    }

    function _remoteTransferWithCallback(
        uint16 dstChainId,
        address from,
        bytes32 to,
        uint256 value,
        uint64 gasForCallback,
        bytes calldata payload,
        AdapterCallParams calldata params
    )
        internal
    {
        uint64 normalizedAmount = _normalizeAmount(value);
        bytes memory _payload =
            Message.encodeTransferWithCallback(from.addressToBytes32(), to, normalizedAmount, gasForCallback, payload);

        address spender = _msgSender();
        Message.Channel channel = Message.Channel(params.adapter);

        if (from != spender) _spendAllowance(from, spender, value);

        _burn(from, value);

        if (channel == Message.Channel.LAYERZERO) {
            bytes memory remoteRouter = lzState.routers[dstChainId];
            bytes memory adapterParams =
                _lzAdapterParam(DEFAULT_GAS_LIMIT, AddressTypeCast.bytes32ToAddress(to), gasForCallback);
            /// TODO: ensure valid remoteRouter
            _lzSend(dstChainId, remoteRouter, _payload, params.refundAddress, address(0), adapterParams, msg.value);
        } else if (channel == Message.Channel.WORMHOLE) {
            bytes32 remoteRouter = wormholeState.routers[dstChainId];
            _whSend(dstChainId, remoteRouter.bytes32ToAddress(), _msgSender(), DEFAULT_GAS_LIMIT, 0, _payload);
        } else {
            revert UnsupportedAction();
        }

        emit RemoteTransfer(dstChainId, to, from, value);
    }

    function _receiveTransfer(uint16 _srcChainId, bytes memory _payload) internal {
        (bytes32 _to, uint64 _amount) = _payload.decodeTransfer();
        address to = _to.bytes32ToAddress();
        uint256 amount = _deNormalizeAmount(_amount);

        _mint(to, amount);

        emit RemoteTransferReceived(_srcChainId, to, amount);
    }

    function _receiveTransferWithCallback(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload,
        Message.Channel _channel
    )
        internal
    {
        (bytes32 _from, bytes32 to, uint64 amount, uint64 gasForCallback, bytes memory payload) =
            _payload.decodeTransferWithCallback();

        uint256 denormalizedAmount = _deNormalizeAmount(amount);
        address _to = to.bytes32ToAddress();

        if (!_isContract(_to)) {
            emit NotContractAccount(_to);
            return;
        }

        if (_channel == Message.Channel.LAYERZERO) {
            _receiveLzTransferWithCallback(
                _srcChainId, _srcAddress, _nonce, _from, _to, denormalizedAmount, gasForCallback, payload
            );
        } else if (_channel == Message.Channel.WORMHOLE) {
            _receiveWhTransferWithCallback(
                _srcChainId, _srcAddress, _nonce, _from, _to, denormalizedAmount, gasForCallback, payload
            );
        }
    }

    function _isContract(address to) internal view returns (bool) {
        return to.code.length > 0;
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    )
        internal
        override
    {
        uint8 action = _payload.payloadId();

        if (action == Message.TRANSFER) {
            _receiveTransfer(_srcChainId, _payload);
        } else if (action == Message.TRANSFER_WITH_CALLBACK) {
            _receiveTransferWithCallback(_srcChainId, _srcAddress, _nonce, _payload, Message.Channel.LAYERZERO);
        } else {
            revert UnsupportedAction();
        }
    }

    function _receiveLzTransferWithCallback(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes32 _from,
        address _to,
        uint256 _amount,
        uint64 _gasForCallback,
        bytes memory _payload
    )
        internal
    {
        bool minted = lzState.minted[_srcChainId][_srcAddress][_nonce];
        if (!minted) {
            _mint(address(this), _amount);
            lzState.minted[_srcChainId][_srcAddress][_nonce] = true;
        }

        uint256 gas = minted ? gasleft() : _gasForCallback;
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(
                this.tryCallback.selector, _srcChainId, _srcAddress, _nonce, _from, _to, _amount, gas, _payload
            )
        );

        if (!success) {
            _storeFailedMessage(_srcChainId, _srcAddress, _nonce, _payload, reason);
        }
    }

    function _receiveWhTransferWithCallback(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes32 _from,
        address _to,
        uint256 _amount,
        uint64 _gasForCallback,
        bytes memory _payload
    )
        internal
    {
        _mint(address(this), _amount);
        (bool success,) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(
                this.tryCallback.selector,
                _srcChainId,
                _srcAddress,
                _nonce,
                _from,
                _to,
                _amount,
                _gasForCallback,
                _payload
            )
        );

        if (!success) {
            // try Refund to the source
            AdapterCallParams memory params =
                AdapterCallParams({ refundAddress: payable(address(this)), adapter: uint8(Message.Channel.WORMHOLE) });
            _remoteTransfer(_srcChainId, address(this), _from, _amount, params);
        }
    }

    function _wormholeReceive(
        bytes memory _payload,
        bytes32 _srcAddress,
        uint16 _srcChainId,
        bytes32 /*_deliveryHash*/
    )
        internal
        override
    {
        uint8 action = _payload.payloadId();

        if (action == Message.TRANSFER) {
            _receiveTransfer(_srcChainId, _payload);
        } else if (action == Message.TRANSFER_WITH_CALLBACK) {
            _receiveTransferWithCallback(
                _srcChainId, abi.encodePacked(_srcAddress), 0, _payload, Message.Channel.WORMHOLE
            );
        } else {
            revert UnsupportedAction();
        }
    }
}
