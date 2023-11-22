// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

interface CommonErrorsAndEvents {
    ///@notice Emitted when a new router contract is registered
    event RouterRegistered(uint16 chainId, bytes32 routerAddress);

    /// @notice Emitted whenever a transfer with callback is initiated to non-contract account
    event NotContractAccount(address to);

    /// @notice Revert when insufficient fund is provided for interchain messaging
    error InsufficientFee();

    /// @notice Thrown when the source address is not a trusted router contract
    error MisTrustedRouter();

    ///@notice Revert when trying to register router for existing chainId
    error RouterAlreadyExists();

    /// @notice Revert if GMPP is already enabled
    error GMPPEnabledAlready();

    /// @notice Revert when the shared decimals is greater than the token decimals
    error InvalidDecimal();

    /// @notice Revert when trying to make an unathorized call
    error NotOminiFungible();

    /// @notice Revert when calling an unsupported action
    error UnsupportedAction();
}
