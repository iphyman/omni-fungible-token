// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

/**
 * @title IReceiveTransferCallback
 * @author Iphyman
 * @notice Interface that defines callback to notify contract account
 * when they receive a token transfer.
 */
interface IReceiveTransferCallback {
    /**
     * @dev A callback function called when a contract receives a token transfer
     *
     * @param srcChainId The GMPP assigned origin chainId
     * @param srcAddress The source account address
     * @param from The account the transfer originated from
     * @param amount The value been sent
     * @param payload Any payload attached to the transfer
     */
    function onReceiveTransfer(
        uint16 srcChainId,
        bytes calldata srcAddress,
        bytes32 from,
        uint256 amount,
        bytes calldata payload
    )
        external;
}
