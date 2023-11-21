// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import {IReceiveTransferCallback} from "./IReceiveTransferCallback.sol";
import {IAdapterCallParamStructure} from "../structures/IAdapterCallParamStructure.sol";

interface IOmniFungible is
    IAdapterCallParamStructure,
    IReceiveTransferCallback
{
    /**
     * @dev A list of perfomable actions
     */
    enum Action {
        TRANSFER,
        TRANSFER_WITH_CALLBACK
    }

    /**
     * @dev Emitted when a remote transfer is initiated from the source chain
     *
     * @param dstChainId GMPP destination chain assigned identifier
     * @param receipient Account to receive `amount` been sent
     * @param from Account on local chain to debit
     * @param amount Value amount been credited to `receipient`
     */
    event RemoteTransfer(
        uint16 indexed dstChainId,
        bytes32 indexed receipient,
        address indexed from,
        uint256 amount
    );
    /**
     * @dev Emitted when the destination chain receives a token
     * transfer from a remote chain
     *
     * @param srcChainId GMPP origin chain assigned identifier
     * @param to Address of EVM account that received the transfer
     * @param amount Value amount received
     */
    event RemoteTransferReceived(
        uint16 indexed srcChainId,
        address indexed to,
        uint256 amount
    );

    /**
     * @dev Moves a `value` amount from `from` to `to` account
     *
     * @param dstChainId GMPP assigned destination chainId
     * @param from account to deduct `value` amount from
     * @param to account to credit `value` amount to
     * @param value value amount
     * @param params a struct defining adapter params
     */
    function transferFrom(
        uint16 dstChainId,
        address from,
        bytes32 to,
        uint256 value,
        AdapterCallParams calldata params
    ) external payable;

    /**
     * @dev Moves a `value` amount from `from` to `to` account and calling
     * the `onReceiveTransfer` callback defined in the `to` address.
     *
     * @param dstChainId GMPP assigned destination chainId
     * @param from account to deduct `value` amount from
     * @param to account to credit `value` amount to
     * @param value value amount
     * @param gasForCallback msg.value amount to pass to callback for gas
     * @param payload any arbitrary data to attach to transfer
     * @param params a struct defining adapter params
     */
    function transferFromWithCallback(
        uint16 dstChainId,
        address from,
        bytes32 to,
        uint256 value,
        uint64 gasForCallback,
        bytes calldata payload,
        AdapterCallParams calldata params
    ) external payable;

    /**
     * @dev Returns the value of tokens in circulation on the local chain
     */
    function circulatingSupply() external view returns (uint256);
}
