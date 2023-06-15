// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {CREATE3Script} from "../base/CREATE3Script.sol";
import {VyperDeployer} from "../../src/lib/VyperDeployer.sol";

contract DeployArbitrumBridgerScript is CREATE3Script, VyperDeployer {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public returns (address bridger) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        address admin = vm.envAddress("ADMIN");

        bridger = create3.deploy(
            getCreate3ContractSalt("ArbitrumBridger"),
            bytes.concat(
                compileContract("bridgers/ArbitrumBridger"),
                abi.encode(getCreate3Contract("OptionsToken"), 1e5, 0.2 gwei, admin)
            )
        );

        vm.stopBroadcast();
    }
}
