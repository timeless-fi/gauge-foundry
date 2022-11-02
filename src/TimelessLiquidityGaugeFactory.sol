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

import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

import {BaseGaugeFactory} from "./BaseGaugeFactory.sol";
import {ILiquidityGauge} from "./interfaces/ILiquidityGauge.sol";

contract TimelessLiquidityGaugeFactory is BaseGaugeFactory {
    using Bytes32AddressLib for address;

    address public admin;
    address public votingEscrowDelegation;

    constructor(ILiquidityGauge gaugeTemplate, address admin_, address votingEscrowDelegation_)
        BaseGaugeFactory(gaugeTemplate)
    {
        admin = admin_;
        votingEscrowDelegation = votingEscrowDelegation_;
    }

    /**
     * @notice Deploys a new gauge.
     * @param lpToken The address of the LP token for which to deploy a gauge
     * @param relativeWeightCap The relative weight cap for the created gauge
     * @return The address of the deployed gauge
     */
    function create(address lpToken, uint256 relativeWeightCap) external returns (address) {
        address gauge = _create(lpToken.fillLast12Bytes());
        ILiquidityGauge(gauge).initialize(lpToken, relativeWeightCap, votingEscrowDelegation, admin);
        return gauge;
    }
}
