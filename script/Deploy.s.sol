// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "bunni/BunniHub.sol";

import "forge-std/Script.sol";

import {Minter} from "../src/Minter.sol";
import {TokenAdmin} from "../src/TokenAdmin.sol";
import {VyperDeployer} from "../src/lib/VyperDeployer.sol";
import {IVotingEscrow} from "../src/interfaces/IVotingEscrow.sol";
import {IERC20Mintable} from "../src/interfaces/IERC20Mintable.sol";
import {ILiquidityGauge} from "../src/interfaces/ILiquidityGauge.sol";
import {IGaugeController} from "../src/interfaces/IGaugeController.sol";
import {TimelessLiquidityGaugeFactory} from "../src/TimelessLiquidityGaugeFactory.sol";

contract DeployScript is Script, VyperDeployer {
    function run()
        public
        returns (
            Minter minter,
            TokenAdmin tokenAdmin,
            IVotingEscrow votingEscrow,
            IGaugeController gaugeController,
            TimelessLiquidityGaugeFactory factory
        )
    {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        address admin = vm.envAddress("ADMIN");
        IERC20Mintable rewardToken = IERC20Mintable(vm.envAddress("REWARD_TOKEN"));
        BunniHub bunniHub = BunniHub(vm.envAddress("BUNNI_HUB"));

        tokenAdmin = new TokenAdmin(rewardToken, admin);
        votingEscrow = IVotingEscrow(
            deployContract("VotingEscrow", abi.encode(rewardToken, "Timeless Voting Escrow", "veTIT", admin))
        );
        gaugeController = IGaugeController(deployContract("GaugeController", abi.encode(votingEscrow, admin)));
        minter = new Minter(tokenAdmin, gaugeController);
        address veDelegation = deployContract(
            "VotingEscrowDelegation", abi.encode(votingEscrow, "Timeless VE-Delegation", "veTIT-BOOST", "", admin)
        );
        ILiquidityGauge liquidityGaugeTemplate =
            ILiquidityGauge(deployContract("TimelessLiquidityGauge", abi.encode(minter)));
        factory = new TimelessLiquidityGaugeFactory(liquidityGaugeTemplate, admin, veDelegation, bunniHub);

        vm.stopBroadcast();
    }
}
