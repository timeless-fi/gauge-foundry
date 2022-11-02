// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import "forge-std/Test.sol";

import {Minter} from "../src/Minter.sol";
import {TokenAdmin} from "../src/TokenAdmin.sol";
import {VyperDeployer} from "../src/lib/VyperDeployer.sol";
import {TestERC20Mintable} from "./mocks/TestERC20Mintable.sol";
import {IVotingEscrow} from "../src/interfaces/IVotingEscrow.sol";
import {IERC20Mintable} from "../src/interfaces/IERC20Mintable.sol";
import {ILiquidityGauge} from "../src/interfaces/ILiquidityGauge.sol";
import {IGaugeController} from "../src/interfaces/IGaugeController.sol";
import {TimelessLiquidityGaugeFactory} from "../src/TimelessLiquidityGaugeFactory.sol";

contract E2ETest is Test {
    address gaugeAdmin;
    address tokenAdminOwner;
    address votingEscrowAdmin;
    address veDelegationAdmin;
    address gaugeControllerAdmin;

    VyperDeployer vyperDeployer;

    Minter minter;
    TokenAdmin tokenAdmin;
    IERC20Mintable mockToken;
    IVotingEscrow votingEscrow;
    IGaugeController gaugeController;
    TimelessLiquidityGaugeFactory factory;

    function setUp() public {
        // init accounts
        gaugeAdmin = makeAddr("gaugeAdmin");
        tokenAdminOwner = makeAddr("tokenAdminOwner");
        votingEscrowAdmin = makeAddr("votingEscrowAdmin");
        veDelegationAdmin = makeAddr("veDelegationAdmin");
        gaugeControllerAdmin = makeAddr("gaugeControllerAdmin");

        // create vyper contract deployer
        vyperDeployer = new VyperDeployer();

        // deploy contracts
        mockToken = IERC20Mintable(address(new TestERC20Mintable()));
        tokenAdmin = new TokenAdmin(mockToken, tokenAdminOwner);
        votingEscrow = IVotingEscrow(
            vyperDeployer.deployContract(
                "VotingEscrow", abi.encode(mockToken, "Timeless Voting Escrow", "veTIT", votingEscrowAdmin)
            )
        );
        gaugeController = IGaugeController(
            vyperDeployer.deployContract("GaugeController", abi.encode(votingEscrow, gaugeControllerAdmin))
        );
        minter = new Minter(tokenAdmin, gaugeController);
        address veDelegation = vyperDeployer.deployContract(
            "VotingEscrowDelegation",
            abi.encode(votingEscrow, "Timeless VE-Delegation", "veTIT-BOOST", "", veDelegationAdmin)
        );
        ILiquidityGauge liquidityGaugeTemplate =
            ILiquidityGauge(vyperDeployer.deployContract("TimelessLiquidityGauge", abi.encode(minter)));
        factory = new TimelessLiquidityGaugeFactory(liquidityGaugeTemplate, gaugeAdmin, veDelegation);

        // activate inflation rewards
        vm.prank(tokenAdminOwner);
        tokenAdmin.activate();
    }

    function test_createGauge() external {
        factory.create(address(mockToken), 1 ether);
    }
}
