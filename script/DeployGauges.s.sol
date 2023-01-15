// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "bunni/src/BunniHub.sol";

import {CREATE3Script, console} from "./base/CREATE3Script.sol";
import {ILiquidityGauge} from "../src/interfaces/ILiquidityGauge.sol";
import {TimelessLiquidityGaugeFactory} from "../src/TimelessLiquidityGaugeFactory.sol";

contract DeployScript is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public returns (ILiquidityGauge[] memory gauges) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        TimelessLiquidityGaugeFactory factory =
            TimelessLiquidityGaugeFactory(getCreate3Contract("TimelessLiquidityGaugeFactory"));

        string[] memory keysJson = vm.envString("INITIAL_GAUGES", "|");
        gauges = new ILiquidityGauge[](keysJson.length);
        for (uint256 i; i < keysJson.length; i++) {
            BunniKey memory key = abi.decode(vm.parseJson(keysJson[i]), (BunniKey));
            gauges[i] = ILiquidityGauge(factory.create(key, 1e18));
        }

        vm.stopBroadcast();
    }
}
