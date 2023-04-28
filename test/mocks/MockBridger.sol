// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice Mock bridger that just does a simple ERC20 transfer
contract MockBridger {
    address public recipient;

    function bridge(address _token, address, /*_to*/ uint256 _amount) external {
        ERC20(_token).transferFrom(msg.sender, recipient, _amount);
    }

    function cost() external pure returns (uint256) {
        return 0;
    }

    function check(address) external pure returns (bool) {
        return true;
    }

    function setRecipient(address newRecipient) external {
        recipient = newRecipient;
    }
}
