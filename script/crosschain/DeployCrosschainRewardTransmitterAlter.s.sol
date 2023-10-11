// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {CREATE3Script} from "../base/CREATE3Script.sol";

import {CrosschainRewardTransmitterAlter} from "../../src/automation/CrosschainRewardTransmitterAlter.sol";

contract DeployCrosschainRewardTransmitterAlterScript is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public returns (CrosschainRewardTransmitterAlter transmitter) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        address admin = vm.envAddress("ADMIN");
        string memory fixVersion = "1.0.1";

        transmitter = CrosschainRewardTransmitterAlter(
            payable(
                create3.deploy(
                    getCreate3ContractSalt("CrosschainRewardTransmitterAlter"),
                    bytes.concat(
                        type(CrosschainRewardTransmitterAlter).creationCode,
                        abi.encode(
                            admin,
                            0x02854a16D39aD1B4b0Cbd60291B509Ce07dad5db,
                            getCreate3Contract("GaugeController"),
                            getCreate3Contract("RootGaugeFactory", fixVersion)
                        )
                    )
                )
            )
        );

        vm.stopBroadcast();
    }
}
