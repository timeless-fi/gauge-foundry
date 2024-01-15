// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {VyperDeployer} from "../../src/lib/VyperDeployer.sol";

interface IConnextBridger {
    function bridge(address _token, address _to, uint256 _amount) external payable;
}

contract ConnextBridgerTest is Test {
    address internal constant CONNEXT = 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6;
    uint32 internal constant DESTINATION_DOMAIN = 1634886255;
    address internal constant LOCKBOX = 0x2b3c399baEB628A29D8d636e7bC495820F9AFB4F;
    ERC20 internal constant OLIT = ERC20(0x627fee87d0D9D2c55098A06ac805Db8F98B158Aa);
    uint256 internal constant XCALL_COST = 0.00021 ether;

    IConnextBridger internal bridger;
    VyperDeployer internal vyperDeployer;

    function setUp() external {
        vyperDeployer = new VyperDeployer();
        bridger = IConnextBridger(
            vyperDeployer.deployContract(
                "bridgers/ConnextBridger", abi.encode(CONNEXT, LOCKBOX, DESTINATION_DOMAIN, XCALL_COST, address(this))
            )
        );

        deal(address(OLIT), address(this), 1 ether);
        OLIT.approve(address(bridger), type(uint256).max);
    }

    function test_bridge() external {
        bridger.bridge{value: XCALL_COST}(address(OLIT), address(this), 1 ether);
    }
}
