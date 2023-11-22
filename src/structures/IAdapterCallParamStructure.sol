// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

interface IAdapterCallParamStructure {
    struct AdapterCallParams {
        address payable refundAddress;
        address zroPaymentAddress;
        bytes lzAdapterParams;
    }
}
