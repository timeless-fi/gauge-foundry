// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import "bunni/BunniHub.sol";
import "bunni/tests/lib/UniswapDeployer.sol";

import "forge-std/Test.sol";

import {Minter} from "../src/Minter.sol";
import {TokenAdmin} from "../src/TokenAdmin.sol";
import {VyperDeployer} from "../src/lib/VyperDeployer.sol";
import {TestERC20Mintable} from "./mocks/TestERC20Mintable.sol";
import {SmartWalletChecker} from "../src/SmartWalletChecker.sol";
import {IVotingEscrow} from "../src/interfaces/IVotingEscrow.sol";
import {IERC20Mintable} from "../src/interfaces/IERC20Mintable.sol";
import {ILiquidityGauge} from "../src/interfaces/ILiquidityGauge.sol";
import {IGaugeController} from "../src/interfaces/IGaugeController.sol";
import {TimelessLiquidityGaugeFactory} from "../src/TimelessLiquidityGaugeFactory.sol";

contract E2ETest is Test, UniswapDeployer {
    address gaugeAdmin;
    address bunniHubOwner;
    address tokenAdminOwner;
    address votingEscrowAdmin;
    address veDelegationAdmin;
    address gaugeControllerAdmin;
    address smartWalletCheckerOwner;

    VyperDeployer vyperDeployer;

    Minter minter;
    BunniHub bunniHub;
    TokenAdmin tokenAdmin;
    IERC20Mintable mockToken;
    IVotingEscrow votingEscrow;
    IUniswapV3Factory uniswapFactory;
    IGaugeController gaugeController;
    TimelessLiquidityGaugeFactory factory;
    SmartWalletChecker smartWalletChecker;

    function setUp() public {
        // init accounts
        gaugeAdmin = makeAddr("gaugeAdmin");
        bunniHubOwner = makeAddr("bunniHubOwner");
        tokenAdminOwner = makeAddr("tokenAdminOwner");
        votingEscrowAdmin = makeAddr("votingEscrowAdmin");
        veDelegationAdmin = makeAddr("veDelegationAdmin");
        gaugeControllerAdmin = makeAddr("gaugeControllerAdmin");
        smartWalletCheckerOwner = makeAddr("smartWalletCheckerOwner");

        // create vyper contract deployer
        vyperDeployer = new VyperDeployer();

        // deploy contracts
        mockToken = IERC20Mintable(address(new TestERC20Mintable()));
        address minterAddress = computeCreateAddress(address(this), 4);
        tokenAdmin = new TokenAdmin(mockToken, Minter(minterAddress), tokenAdminOwner);
        votingEscrow = IVotingEscrow(
            vyperDeployer.deployContract(
                "VotingEscrow", abi.encode(mockToken, "Timeless Voting Escrow", "veTIT", votingEscrowAdmin)
            )
        );
        gaugeController = IGaugeController(
            vyperDeployer.deployContract("GaugeController", abi.encode(votingEscrow, gaugeControllerAdmin))
        );
        minter = new Minter(tokenAdmin, gaugeController);
        assert(address(minter) == minterAddress);
        address veDelegation = vyperDeployer.deployContract(
            "VotingEscrowDelegation",
            abi.encode(votingEscrow, "Timeless VE-Delegation", "veTIT-BOOST", "", veDelegationAdmin)
        );
        ILiquidityGauge liquidityGaugeTemplate =
            ILiquidityGauge(vyperDeployer.deployContract("TimelessLiquidityGauge", abi.encode(minter)));
        uniswapFactory = IUniswapV3Factory(deployUniswapV3Factory());
        bunniHub = new BunniHub(uniswapFactory, bunniHubOwner, 0);
        factory = new TimelessLiquidityGaugeFactory(liquidityGaugeTemplate, gaugeAdmin, veDelegation, bunniHub);

        // activate inflation rewards
        vm.prank(tokenAdminOwner);
        tokenAdmin.activate();

        // set smart wallet checker
        address[] memory initialAllowedAddresses = new address[](0);
        smartWalletChecker = new SmartWalletChecker(smartWalletCheckerOwner, initialAllowedAddresses);
        vm.startPrank(votingEscrowAdmin);
        votingEscrow.commit_smart_wallet_checker(address(smartWalletChecker));
        votingEscrow.apply_smart_wallet_checker();
        vm.stopPrank();
    }

    function test_createGauge() external {
        // deploy mock tokens and uniswap pool
        TestERC20Mintable tokenA = new TestERC20Mintable();
        TestERC20Mintable tokenB = new TestERC20Mintable();
        uint24 fee = 500;
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapFactory.createPool(address(tokenA), address(tokenB), fee));
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        // deploy bunni token
        BunniKey memory key = BunniKey({pool: pool, tickLower: -100, tickUpper: 100});
        bunniHub.deployBunniToken(key);

        // create gauge
        factory.create(key, 1 ether);
    }
}
