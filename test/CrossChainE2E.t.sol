// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import {BunniHub, BunniKey, IBunniToken} from "bunni/src/BunniHub.sol";
import {IBunniHub} from "bunni/src/interfaces/IBunniHub.sol";
import {UniswapDeployer} from "bunni/src/tests/lib/UniswapDeployer.sol";
import {SwapRouter} from "bunni/lib/v3-periphery/contracts/SwapRouter.sol";
import {TickMath} from "bunni/lib/v3-core/contracts/libraries/TickMath.sol";
import {ISwapRouter} from "bunni/lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "bunni/lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "bunni/lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {CREATE3Factory} from "create3-factory/src/CREATE3Factory.sol";

import "forge-std/Test.sol";

import {WETH} from "solmate/tokens/WETH.sol";

import {UniswapPoorOracle} from "uniswap-poor-oracle/UniswapPoorOracle.sol";

import {MockVeBeacon} from "ve-beacon/test/mocks/MockVeBeacon.sol";
import {MockVeRecipient} from "ve-beacon/test/mocks/MockVeRecipient.sol";

import {Minter} from "../src/Minter.sol";
import {TokenAdmin} from "../src/TokenAdmin.sol";
import {VyperDeployer} from "../src/lib/VyperDeployer.sol";
import {TestERC20Mintable} from "./mocks/TestERC20Mintable.sol";
import {SmartWalletChecker} from "../src/SmartWalletChecker.sol";
import {IVotingEscrow} from "../src/interfaces/IVotingEscrow.sol";
import {IERC20Mintable} from "../src/interfaces/IERC20Mintable.sol";
import {IGaugeController} from "../src/interfaces/IGaugeController.sol";
import {IVotingEscrowDelegation} from "../src/interfaces/IVotingEscrowDelegation.sol";
import {IRootGauge} from "../src/interfaces/IRootGauge.sol";
import {IRootGaugeFactory} from "../src/interfaces/IRootGaugeFactory.sol";
import {IChildGauge} from "../src/interfaces/IChildGauge.sol";
import {IChildGaugeFactory} from "../src/interfaces/IChildGaugeFactory.sol";
import {MockBridger} from "./mocks/MockBridger.sol";

contract CrossChainE2ETest is Test, UniswapDeployer {
    string constant version = "1.0.0";
    uint24 constant FEE = 500;
    uint256 constant IN_RANGE_THRESHOLD = 5e17;
    uint256 constant RECORDING_MIN_LENGTH = 1 hours;
    uint256 constant RECORDING_MAX_LENGTH = 1 hours + 30 minutes;
    int24 constant TICK_LOWER = -10;
    int24 constant TICK_UPPER = 10;

    address gaugeAdmin;
    address bunniHubOwner;
    address tokenAdminOwner;
    address votingEscrowAdmin;
    address veDelegationAdmin;
    address gaugeControllerAdmin;
    address smartWalletCheckerOwner;

    VyperDeployer vyperDeployer;
    CREATE3Factory create3;

    WETH weth;
    BunniKey key;
    Minter minter;
    BunniHub bunniHub;
    SwapRouter router;
    IUniswapV3Pool pool;
    TokenAdmin tokenAdmin;
    TestERC20Mintable tokenA;
    TestERC20Mintable tokenB;
    UniswapPoorOracle oracle;
    IERC20Mintable mockToken;
    IVotingEscrow votingEscrow;
    IUniswapV3Factory uniswapFactory;
    IGaugeController gaugeController;
    IVotingEscrowDelegation veDelegation;
    IRootGaugeFactory rootFactory;
    IChildGaugeFactory childFactory;
    SmartWalletChecker smartWalletChecker;
    MockVeBeacon beacon;
    MockVeRecipient veRecipient;
    MockBridger bridger;

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
        veDelegation = IVotingEscrowDelegation(
            vyperDeployer.deployContract(
                "VotingEscrowDelegation",
                abi.encode(votingEscrow, "Timeless VE-Delegation", "veTIT-BOOST", "", veDelegationAdmin)
            )
        );
        oracle = new UniswapPoorOracle(IN_RANGE_THRESHOLD, RECORDING_MIN_LENGTH, RECORDING_MAX_LENGTH);
        uniswapFactory = IUniswapV3Factory(deployUniswapV3Factory());
        bunniHub = new BunniHub(uniswapFactory, bunniHubOwner, 0);
        weth = new WETH();
        router = new SwapRouter(address(uniswapFactory), address(weth));

        // deploy create3 factory
        create3 = new CREATE3Factory();

        // deploy ve beacon and recipient
        beacon = MockVeBeacon(
            create3.deploy(
                getCreate3ContractSalt("MockVeBeacon"),
                bytes.concat(
                    type(MockVeBeacon).creationCode, abi.encode(votingEscrow, getCreate3Contract("MockVeRecipient"))
                )
            )
        );
        veRecipient = MockVeRecipient(
            create3.deploy(
                getCreate3ContractSalt("MockVeRecipient"),
                bytes.concat(
                    type(MockVeRecipient).creationCode, abi.encode(getCreate3Contract("MockVeBeacon"), address(this))
                )
            )
        );

        // deploy root gauge and child gauge factories
        {
            childFactory = IChildGaugeFactory(
                vyperDeployer.deployContract("ChildGaugeFactory", abi.encode(mockToken, address(this), bunniHub))
            );
            IChildGauge childGaugeTemplate =
                IChildGauge(vyperDeployer.deployContract("ChildGauge", abi.encode(mockToken, childFactory, oracle)));
            childFactory.set_implementation(address(childGaugeTemplate));

            // use veRecipient as voting escrow
            childFactory.set_voting_escrow(address(veRecipient));
        }
        {
            rootFactory = IRootGaugeFactory(vyperDeployer.deployContract("RootGaugeFactory", abi.encode(address(this))));
            IRootGauge rootGaugeTemplate = IRootGauge(vyperDeployer.deployContract("RootGauge", abi.encode(minter)));
            rootFactory.set_implementation(address(rootGaugeTemplate));
            bridger = new MockBridger();
            rootFactory.set_bridger(block.chainid, address(bridger));
        }

        // deploy mock uniswap pool
        tokenA = new TestERC20Mintable();
        tokenB = new TestERC20Mintable();
        pool = IUniswapV3Pool(uniswapFactory.createPool(address(tokenA), address(tokenB), FEE));
        pool.initialize(TickMath.getSqrtRatioAtTick(0));
        vm.label(address(pool), "UniswapV3Pool");
        key = BunniKey({pool: pool, tickLower: TICK_LOWER, tickUpper: TICK_UPPER});
        bunniHub.deployBunniToken(key);

        // token approvals
        tokenA.approve(address(router), type(uint256).max);
        tokenA.approve(address(bunniHub), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenB.approve(address(bunniHub), type(uint256).max);

        // provide liquidity
        tokenA.mint(address(this), 1e18);
        tokenB.mint(address(this), 1e18);
        bunniHub.deposit(
            IBunniHub.DepositParams({
                key: key,
                amount0Desired: 1e18,
                amount1Desired: 1e18,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp,
                recipient: address(this)
            })
        );

        // activate inflation rewards
        vm.prank(tokenAdminOwner);
        tokenAdmin.activate();

        // add gauge type
        vm.prank(gaugeControllerAdmin);
        gaugeController.add_type("Cross Chain", 1);

        // set smart wallet checker
        address[] memory initialAllowedAddresses = new address[](1);
        initialAllowedAddresses[0] = address(this);
        smartWalletChecker = new SmartWalletChecker(smartWalletCheckerOwner, initialAllowedAddresses);
        vm.startPrank(votingEscrowAdmin);
        votingEscrow.commit_smart_wallet_checker(address(smartWalletChecker));
        votingEscrow.apply_smart_wallet_checker();
        vm.stopPrank();
    }

    /**
     * Gauge interaction tests
     */

    function test_gauge_stakeRewards() external {
        uint256 numWeeksWait = 4;

        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key));
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        // approve gauge
        vm.prank(gaugeControllerAdmin);
        gaugeController.add_gauge(address(rootGauge), 0, 1);

        // lock tokens in voting escrow
        mockToken.mint(address(this), 1 ether);
        mockToken.approve(address(votingEscrow), type(uint256).max);
        votingEscrow.create_lock(1 ether, block.timestamp + 200 weeks);

        // push vetoken balance from beacon to recipient
        beacon.broadcastVeBalance(address(this), 0, 0, 0);

        // stake liquidity in child gauge
        IBunniToken bunniToken = bunniHub.getBunniToken(key);
        bunniToken.approve(address(childGauge), type(uint256).max);
        uint256 amount = bunniToken.balanceOf(address(this));
        childGauge.deposit(amount);

        // claim rewards every week
        bridger.setRecipient(address(childGauge));
        // every time `childFactory.mint` is called the rewards
        // are fully distributed after the current week ends
        // thus we need to wait one more week
        for (uint256 i = 0; i < numWeeksWait + 1; i++) {
            skip(1 weeks);
            rootFactory.transmit_emissions(address(rootGauge));
            childFactory.mint(address(childGauge));
        }

        // check balance
        uint256 expectedAmount = tokenAdmin.INITIAL_RATE() * (numWeeksWait - 1) * (1 weeks); // first week has no rewards
        assertApproxEqRel(mockToken.balanceOf(address(this)), expectedAmount, 1e12, "balance incorrect");
    }

    function test_gauge_stakeAndUnstake() external {
        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key));
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        // approve gauge
        vm.prank(gaugeControllerAdmin);
        gaugeController.add_gauge(address(rootGauge), 0, 1);

        // lock tokens in voting escrow
        mockToken.mint(address(this), 1 ether);
        mockToken.approve(address(votingEscrow), type(uint256).max);
        votingEscrow.create_lock(1 ether, block.timestamp + 200 weeks);

        // push vetoken balance from beacon to recipient
        beacon.broadcastVeBalance(address(this), 0, 0, 0);

        // stake liquidity in child gauge
        IBunniToken bunniToken = bunniHub.getBunniToken(key);
        bunniToken.approve(address(childGauge), type(uint256).max);
        uint256 amount = bunniToken.balanceOf(address(this));
        childGauge.deposit(amount);

        // check balances
        assertEq(bunniToken.balanceOf(address(this)), 0, "user still has LP tokens after deposit");
        assertEq(bunniToken.balanceOf(address(childGauge)), amount, "LP tokens didn't get transferred to gauge");
        assertEq(childGauge.balanceOf(address(this)), amount, "user didn't get gauge tokens");

        // withdraw liquidity
        childGauge.withdraw(amount);

        // check balances
        assertEq(bunniToken.balanceOf(address(this)), amount, "user didn't receive LP tokens after withdraw");
        assertEq(bunniToken.balanceOf(address(childGauge)), 0, "gauge still has LP tokens after withdraw");
        assertEq(childGauge.balanceOf(address(this)), 0, "user still has gauge tokens after withdraw");
    }

    /**
     * Internal helpers
     */

    function getCreate3Contract(string memory name) internal view virtual returns (address) {
        return create3.getDeployed(address(this), getCreate3ContractSalt(name));
    }

    function getCreate3ContractSalt(string memory name) internal view virtual returns (bytes32) {
        return keccak256(bytes(string.concat(name, "-v", version)));
    }
}