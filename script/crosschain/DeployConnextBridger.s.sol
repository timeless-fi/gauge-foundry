// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {CREATE3Script} from "../base/CREATE3Script.sol";
import {VyperDeployer} from "../../src/lib/VyperDeployer.sol";

contract DeployConnextBridgerScript is CREATE3Script, VyperDeployer {
    address internal constant CONNEXT = 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6; // Connext mainnet
    uint32 internal constant DESTINATION_DOMAIN = 1634886255; // Arbitrum
    address internal constant LOCKBOX = 0x2b3c399baEB628A29D8d636e7bC495820F9AFB4F; // Mainnet oLIT lockbox
    address internal constant OLIT = 0x627fee87d0D9D2c55098A06ac805Db8F98B158Aa; // Mainnet oLIT
    uint256 internal constant XCALL_COST = 0.00021 ether;

    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public returns (address bridger) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        address admin = vm.envAddress("ADMIN");

        bridger = create3.deploy(
            getCreate3ContractSalt("ConnextBridger"),
            bytes.concat(
                compileContract("bridgers/ConnextBridger"),
                abi.encode(CONNEXT, LOCKBOX, DESTINATION_DOMAIN, XCALL_COST, admin)
            )
        );

        vm.stopBroadcast();
    }
}
