// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {CREATE3Script} from "../base/CREATE3Script.sol";
import {IBridger} from "../../src/interfaces/IBridger.sol";
import {IRootGauge} from "../../src/interfaces/IRootGauge.sol";
import {IGaugeController} from "../../src/interfaces/IGaugeController.sol";
import {IRootGaugeFactory} from "../../src/interfaces/IRootGaugeFactory.sol";

contract TransmitCrosschainRewardsScript is CREATE3Script {
    IGaugeController public constant gaugeController = IGaugeController(0x901c8aA6A61f74aC95E7f397E22A0Ac7c1242218);
    IRootGaugeFactory public constant rootGaugeFactory = IRootGaugeFactory(0xe4666F0937B62d64C10316DB0b7061549F87e95F);

    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        (address[] memory gaugeList, uint256 cost) = checker();
        rootGaugeFactory.transmit_emissions_multiple{value: cost}(gaugeList);

        vm.stopBroadcast();
    }

    function checker() internal view returns (address[] memory gaugeList, uint256 cost) {
        // construct gauge list
        uint256 numGauges = uint256(int256(gaugeController.n_gauges()));
        gaugeList = new address[](numGauges);
        uint256 numRootGauges;
        for (uint256 i; i < numGauges;) {
            IRootGauge gauge = IRootGauge(gaugeController.gauges(i));
            try gauge.bridger() returns (address bridger) {
                // is root gauge
                if (bridger != address(0)) {
                    gaugeList[numRootGauges] = address(gauge);
                    unchecked {
                        ++numRootGauges;
                    }
                    cost += IBridger(bridger).cost();
                }
            } catch {}

            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(gaugeList, numRootGauges) // shorten gaugeList to the actual number of root gauges
        }
    }
}
