// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice Mock bridger that just does a simple ERC20 transfer
contract MockBridger {
    address public recipient;
    uint256 internal _cost;
    mapping(address => address) public recipientOfSender;

    error MockBridger__MsgValueInsufficient();

    function bridge(address _token, address, /*_to*/ uint256 _amount) external payable {
        if (msg.value < _cost) revert MockBridger__MsgValueInsufficient();
        address _recipientOfSender = recipientOfSender[msg.sender];
        address _recipient = _recipientOfSender == address(0) ? recipient : _recipientOfSender;
        ERC20(_token).transferFrom(msg.sender, _recipient, _amount);
        if (address(this).balance != 0) payable(msg.sender).transfer(address(this).balance);
    }

    function cost() external view returns (uint256) {
        return _cost;
    }

    function check(address) external pure returns (bool) {
        return true;
    }

    function setRecipient(address newRecipient) external {
        recipient = newRecipient;
    }

    function setRecipientOfSender(address sender, address newRecipient) external {
        recipientOfSender[sender] = newRecipient;
    }

    function setCost(uint256 newCost) external {
        _cost = newCost;
    }
}
