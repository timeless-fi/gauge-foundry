// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

import {Owned} from "solmate/auth/Owned.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Smart wallet checker
/// @notice Maintains an allowlist of smart contracts that can interact with
/// the VotingEscrow contract
contract SmartWalletChecker is Owned {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using EnumerableSet for EnumerableSet.AddressSet;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error SmartWalletChecker__AddressNotAllowlisted();
    error SmartWalletChecker__AddressAlreadyAllowlisted();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event ContractAddressAdded(address contractAddress);
    event ContractAddressRemoved(address contractAddress);

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    EnumerableSet.AddressSet private _allowlistedAddresses;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address owner_, address[] memory initialAllowedAddresses) Owned(owner_) {
        uint256 addressesLength = initialAllowedAddresses.length;
        for (uint256 i = 0; i < addressesLength; ++i) {
            _allowlistAddress(initialAllowedAddresses[i]);
        }
    }

    /// -----------------------------------------------------------------------
    /// View functions
    /// -----------------------------------------------------------------------

    function check(address contractAddress) external view returns (bool) {
        return _allowlistedAddresses.contains(contractAddress);
    }

    function getAllowlistedAddress(uint256 index) external view returns (address) {
        return _allowlistedAddresses.at(index);
    }

    function getAllowlistedAddressesLength() external view returns (uint256) {
        return _allowlistedAddresses.length();
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    function allowlistAddress(address contractAddress) external onlyOwner {
        _allowlistAddress(contractAddress);
    }

    function denylistAddress(address contractAddress) external onlyOwner {
        if (!_allowlistedAddresses.remove(contractAddress)) revert SmartWalletChecker__AddressNotAllowlisted();
        emit ContractAddressRemoved(contractAddress);
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _allowlistAddress(address contractAddress) internal {
        if (!_allowlistedAddresses.add(contractAddress)) revert SmartWalletChecker__AddressAlreadyAllowlisted();
        emit ContractAddressAdded(contractAddress);
    }
}
