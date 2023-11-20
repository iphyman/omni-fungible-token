// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

interface IOmniFungible {
    /**
     * @dev Returns the value of tokens in circulation on the local chain
     */
    function circulatingSupply() external view returns (uint256);
}
