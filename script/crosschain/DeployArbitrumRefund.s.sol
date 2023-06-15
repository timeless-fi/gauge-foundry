// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {LibString} from "solmate/utils/LibString.sol";

import {CREATE3Script} from "../base/CREATE3Script.sol";
import {VyperDeployer} from "../../src/lib/VyperDeployer.sol";

contract DeployArbitrumRefundScript is CREATE3Script, VyperDeployer {
    using LibString for uint256;

    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public returns (address bridger) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        require(block.chainid == 42161, "Not Arbitrum");

        address owner = vm.envAddress(string.concat("OWNER_", block.chainid.toString()));

        bridger = create3.deploy(
            getCreate3ContractSalt("ArbitrumBridger"),
            bytes.concat(compileContract("bridgers/ArbitrumRefund"), abi.encode(owner))
        );

        vm.stopBroadcast();
    }
}
