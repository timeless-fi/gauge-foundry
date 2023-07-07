// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {LibString} from "solmate/utils/LibString.sol";

import {CREATE3Script} from "../base/CREATE3Script.sol";
import {VyperDeployer} from "../../src/lib/VyperDeployer.sol";

import {IChildGauge} from "../../src/interfaces/IChildGauge.sol";
import {IChildGaugeFactory} from "../../src/interfaces/IChildGaugeFactory.sol";

contract DeployChildGaugeFactoryScript is CREATE3Script, VyperDeployer {
    using LibString for uint256;

    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public returns (IChildGauge childGaugeTemplate, IChildGaugeFactory childGaugeFactory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        address token = vm.envAddress(string.concat("TOKEN_", block.chainid.toString()));
        address owner = vm.envAddress(string.concat("OWNER_", block.chainid.toString()));

        string memory fixVersion = "1.0.1";

        childGaugeTemplate = IChildGauge(
            create3.deploy(
                getCreate3ContractSalt("RootGauge", fixVersion),
                bytes.concat(
                    compileContract("ChildGauge"),
                    abi.encode(
                        getCreate3Contract("RootGaugeFactory", fixVersion), getCreate3Contract("UniswapPoorOracle")
                    )
                )
            )
        );

        childGaugeFactory = IChildGaugeFactory(
            create3.deploy(
                getCreate3ContractSalt("RootGaugeFactory", fixVersion),
                bytes.concat(
                    compileContract("ChildGaugeFactory"),
                    abi.encode(
                        token, owner, vm.envAddress("BUNNI_HUB"), getCreate3Contract("VeRecipient"), childGaugeTemplate
                    )
                )
            )
        );

        require(childGaugeTemplate.factory() == address(childGaugeFactory));

        vm.stopBroadcast();
    }
}
