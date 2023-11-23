// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

interface WormholeAdapterErrorsAndEvents {
    /// @notice Revert if wormhole is zero address
    error InvalidWormholeEndpoint();

    /// @notice Revert when wormhole chainId is zero
    error InvalidWormholeChainId();

    /// @notice Revert when wormhole relayer is invalid
    error InvalidWormholeRelayer();

    /// @notice Revert when `msg.sender` is not the wormhole relayer
    error OnlyWormholeRelayerAllowed();

    /// @notice Revert when trying to process an already processed wormhole message
    error WormholeMessageProcessed();

    /// @notice Revert when the message is received from non-whitelisted router
    error UnAuthorizedWormholeRouter();
}
