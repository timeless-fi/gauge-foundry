// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBridger {
    function cost() external view returns (uint256);
    function bridge(address token, address dest, uint256 amount) external payable;
}
