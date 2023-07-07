// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {CREATE3Script} from "../base/CREATE3Script.sol";
import {VyperDeployer} from "../../src/lib/VyperDeployer.sol";

import {IRootGauge} from "../../src/interfaces/IRootGauge.sol";
import {IRootGaugeFactory} from "../../src/interfaces/IRootGaugeFactory.sol";

contract DeployRootGaugeFactoryScript is CREATE3Script, VyperDeployer {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public returns (IRootGauge rootGaugeTemplate, IRootGaugeFactory rootGaugeFactory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        address admin = vm.envAddress("ADMIN");

        string memory fixVersion = "1.0.1";

        rootGaugeTemplate = IRootGauge(
            create3.deploy(
                getCreate3ContractSalt("RootGauge", fixVersion),
                bytes.concat(compileContract("RootGauge"), abi.encode(getCreate3Contract("Minter")))
            )
        );

        rootGaugeFactory = IRootGaugeFactory(
            create3.deploy(
                getCreate3ContractSalt("RootGaugeFactory", fixVersion),
                bytes.concat(compileContract("RootGaugeFactory"), abi.encode(admin, rootGaugeTemplate))
            )
        );

        vm.stopBroadcast();
    }
}
