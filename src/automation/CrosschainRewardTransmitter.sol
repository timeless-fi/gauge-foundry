// SPDX-License-Identifier: GPL-3.0
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IBridger} from "../interfaces/IBridger.sol";
import {IRootGauge} from "../interfaces/IRootGauge.sol";
import {IGelatoResolver} from "../interfaces/IGelatoResolver.sol";
import {IGaugeController} from "../interfaces/IGaugeController.sol";
import {IRootGaugeFactory} from "../interfaces/IRootGaugeFactory.sol";

contract CrosschainRewardTransmitter is IGelatoResolver, Owned {
    using SafeTransferLib for address payable;

    error CrosschainRewardTransmitter__Unauthorized();

    uint256 internal constant WINDOW = 2 hours;

    address public immutable transmitter;
    IGaugeController public immutable gaugeController;
    IRootGaugeFactory public immutable rootGaugeFactory;

    constructor(
        address owner_,
        address transmitter_,
        IGaugeController gaugeController_,
        IRootGaugeFactory rootGaugeFactory_
    ) Owned(owner_) {
        transmitter = transmitter_;
        gaugeController = gaugeController_;
        rootGaugeFactory = rootGaugeFactory_;
    }

    function transmitMultiple(address[] calldata gaugeList, uint256 cost) external {
        if (msg.sender != transmitter) revert CrosschainRewardTransmitter__Unauthorized();
        rootGaugeFactory.transmit_emissions_multiple{value: cost}(gaugeList);
    }

    function checker() external view override returns (bool canExec, bytes memory execPayload) {
        // ensure time is slightly before next epoch
        uint256 epoch = block.timestamp / (1 weeks);
        uint256 nextEpochStart = (epoch + 1) * (1 weeks);
        if (block.timestamp < nextEpochStart - WINDOW) return (false, bytes(""));

        // construct gauge list
        uint256 numGauges = uint256(int256(gaugeController.n_gauges()));
        address[] memory gaugeList = new address[](numGauges);
        uint256 numRootGauges;
        uint256 cost;
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

        // cannot exec if contract doesn't have enough balance
        if (cost > address(this).balance) return (false, bytes(""));

        return (true, abi.encodeCall(CrosschainRewardTransmitter.transmitMultiple, (gaugeList, cost)));
    }

    receive() external payable {}

    function drain(address payable recipient) external onlyOwner {
        recipient.safeTransferETH(address(this).balance);
    }
}
