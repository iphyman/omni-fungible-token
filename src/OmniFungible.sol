// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import {IOmniFungible} from "./interfaces/IOmniFungible.sol";
import {IReceiveTransferCallback} from "./interfaces/IReceiveTransferCallback.sol";

import {AddressTypeCast} from "./libraries/AddressTypeCast.sol";
import {Message} from "./libraries/Message.sol";
import {Ownable} from "lib/openzeppelin-contracts";
import {ERC20} from "lib/openzeppelin-contracts";

import {LayerZeroAdapter} from "./layerzero/LayerZeroAdapter.sol";

contract OmniFungible is IOmniFungible, Ownable, ERC20, LayerZeroAdapter {
    using Message for bytes;
    using AddressTypeCast for bytes32;
    using AddressTypeCast for address;

    constructor(
        address _owner,
        address _lzEndpoint,
        string memory _name,
        string memory _symbol
    ) Ownable(_owner) LayerZeroAdapter(_lzEndPoint) ERC20(_name, _symbol) {}

    /// @inheritdoc IOmniFungible
    function transferFrom(
        uint16 dstChainId,
        address from,
        bytes32 to,
        uint256 value,
        AdapterCallParams calldata params
    ) external payable override {
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
    ) external payable override {
        _remoteTransferWithCallback(
            dstChainId,
            from,
            to,
            value,
            gasForCallback,
            payload,
            params
        );
    }

    /// @inheritdoc IOmniFungible
    function circulatingSupply() external view override returns (uint256) {
        return 400;
    }

    function _decimals(address token) internal view returns (uint8) {
        (, bytes memory queriedDecimals) = token.staticcall(
            abi.encodeWithSignature("decimals()")
        );

        return abi.decode(queriedDecimals, (uint8));
    }

    function _normalizeAmount(
        uint256 _amount,
        uint8 _decimals
    ) internal pure returns (uint64 amount) {
        amount = uint64(_amount);

        if (_decimals > 8) {
            amount /= 10 ** (_decimals - 8);
        }

        return amount;
    }

    function _deNormalizeAmount(
        uint64 _amount,
        uint8 _decimals
    ) internal returns (uint256 amount) {
        amount = uint256(_amount);

        if (_decimals > 8) {
            amount *= 10 ** (_decimals - 8);
        }

        return amount;
    }

    function _transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        address spender = _msgSender();

        if (_from != address(this) && _from != spender)
            _spendAllowance(_from, spender, _amount);

        _transfer(_from, _to, _amount);
    }

    function tryCallback(
        uint16 srcChainId,
        bytes calldata srcAddress,
        uint64 /**nonce*/,
        bytes32 from,
        address to,
        uint256 amount,
        uint256 gasForCall,
        bytes calldata payload
    ) public {
        if (_msgSender() != address(this)) revert NotOmniFungible();

        _transferFrom(address(this), to, amount);
        emit RemoteTransferReceived(srcChainId, to, amount);

        IReceiveTransferCallback(to).onReceiveTransfer{gas: gasForCall}(
            srcChainId,
            srcAddress,
            from,
            amount,
            payload
        );
    }

    function _remoteTransfer(
        uint16 dstChainId,
        address from,
        bytes32 to,
        uint256 value,
        AdapterCallParams calldata params
    ) internal {
        uint64 normalizedAmount = _normalizeAmount(
            value,
            _decimals(address(this))
        );
        bytes memory payload = Message.encodeTransfer(to, normalizedAmount);

        address spender = _msgSender();
        bytes memory remoteRouter = _lzState.routers[dstChainId];
        // bytes32 remote = remoteRouter.remote();

        if (from != spender) _spendAllowance(from, spender, value);

        _burn(_from, value);
        _lzSend(
            dstChainId,
            remoteRouter,
            payload,
            params.refundAddress,
            params.zroPaymentAddress,
            params.lzAdapterParams,
            msg.value
        );

        emit RemoteTransfer(dstChainId, to, from, value);
    }

    function _remoteTransferWithCallback(
        uint16 dstChainId,
        address from,
        bytes32 to,
        uint256 value,
        uint64 gasForCallback,
        bytes calldata message,
        AdapterCallParams calldata params
    ) internal {
        uint64 normalizedAmount = _normalizeAmount(
            value,
            _decimals(address(this))
        );
        bytes memory payload = Message.encodeTransferWithCallback(
            from,
            to,
            normalizedAmount,
            gasForCallback,
            message
        );

        address spender = _msgSender();
        bytes memory remoteRouter = _lzState.routers[dstChainId];

        if (from != spender) _spendAllowance(from, spender, value);

        _burn(_from, value);
        _lzSend(
            dstChainId,
            remoteRouter,
            payload,
            params.refundAddress,
            params.zroPaymentAddress,
            params.lzAdapterParams,
            msg.value
        );

        emit RemoteTransfer(dstChainId, to, from, value);
    }

    function _receiveTransfer(
        uint16 srcChainId,
        bytes memory payload
    ) internal {
        (bytes32 _to, uint64 _amount) = payload.decodeTransfer();
        address to = _to.bytes32ToAddress();
        uint256 amount = _deNormalizeAmount(_amount, _decimals(address(this)));

        _mint(to, amount);

        emit RemoteTransferReceived(srcChainId, to, amount);
    }

    function _receiveTransferWithCallback(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory _payload
    ) internal {
        (
            bytes32 from,
            bytes32 to,
            uint64 amount,
            uint64 gasForCallback,
            bytes memory payload
        ) = _payload.decodeTransferWithCallback();
        bool minted = _lzState.minted[srcChainId][srcAddress][nonce];
        uint256 denormalizedAmount = _deNormalizeAmount(
            amount,
            _decimals(address(this))
        );

        if (!minted) {
            _mint(address(this), denormalizedAmount);
            _lzState.minted[srcChainId][srcAddress][nonce] = true;
        }

        if (!_isContract(to)) {
            emit NotContractAccount(to);
            return;
        }

        uint256 gas = minted ? gasleft() : gasForCallback;
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(
                this.tryCallback.selector,
                srcChainId,
                srcAddress,
                nonce,
                from,
                to,
                amount,
                gas,
                payload
            )
        );

        if (!success) {
            _storeFailedMessage(srcChainId, srcAddress, nonce, payload, reason);
        }
    }

    function _isContract(address to) internal view returns (bool) {
        return to.code.length > 0;
    }

    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) internal override {
        uint8 action = payload.payloadId();

        if (action == Message.TRANSFER) {
            _receiveTransfer(srcChainId, payload);
        } else if (action == Message.TRANSFER_WITH_CALLBACK) {
            _receiveTransferWithCallback(
                srcChainId,
                srcAddress,
                nonce,
                payload
            );
        } else {
            revert UnSupportedAction();
        }
    }
}
