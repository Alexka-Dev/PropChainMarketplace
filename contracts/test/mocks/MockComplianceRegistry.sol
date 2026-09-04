// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.29;

import {IComplianceRegistry} from "@src/PropChainMarketplace.sol";

contract MockComplianceRegistry is IComplianceRegistry {
    mapping(address => bool) private _verifiedUsers;

    function setVerified(address account, bool status) external {
        _verifiedUsers[account] = status;
    }

    function isVerified(address account) external view override returns (bool) {
        return _verifiedUsers[account];
    }
}