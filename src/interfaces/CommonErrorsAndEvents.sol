// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

interface CommonErrorsAndEvents {
    ///@notice Emitted when a new router contract is registered
    event RouterRegistered(uint16 chainId, bytes32 routerAddress);

    /// @notice Revert when insufficient fund is provided for interchain messaging
    error InsufficientFee();

    /// @notice Thrown when the source address is not a trusted router contract
    error MisTrustedRouter();

    ///@notice Revert when trying to register router for existing chainId
    error RouterAlreadyExists();

    /// @notice Revert if GMPP is already enabled
    error GMPPEnabledAlready();
}
