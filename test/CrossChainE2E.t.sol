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
import {CrosschainRewardTransmitter} from "../src/automation/CrosschainRewardTransmitter.sol";

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
    CrosschainRewardTransmitter transmitter;

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
            IChildGauge childGaugeTemplate = IChildGauge(
                create3.deploy(
                    getCreate3ContractSalt("ChildGauge"),
                    bytes.concat(
                        vyperDeployer.compileContract("ChildGauge"),
                        abi.encode(getCreate3Contract("ChildGaugeFactory"), oracle)
                    )
                )
            );
            childFactory = IChildGaugeFactory(
                create3.deploy(
                    getCreate3ContractSalt("ChildGaugeFactory"),
                    bytes.concat(
                        vyperDeployer.compileContract("ChildGaugeFactory"),
                        abi.encode(mockToken, address(this), bunniHub, veRecipient, childGaugeTemplate)
                    )
                )
            );
        }
        {
            IRootGauge rootGaugeTemplate = IRootGauge(vyperDeployer.deployContract("RootGauge", abi.encode(minter)));
            rootFactory = IRootGaugeFactory(
                vyperDeployer.deployContract("RootGaugeFactory", abi.encode(address(this), rootGaugeTemplate))
            );
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

        // deploy transmitter
        transmitter = new CrosschainRewardTransmitter(address(this), address(this), gaugeController, rootFactory);
    }

    /**
     * Gauge interaction tests
     */

    function test_gauge_stakeRewards(uint256 numWeeksWait) external {
        numWeeksWait = bound(numWeeksWait, 1, 50);

        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));
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

    function test_gauge_stakeRewards_bridgerCost(uint256 numWeeksWait, uint256 cost, uint256 extraValue) external {
        numWeeksWait = bound(numWeeksWait, 1, 50);
        cost = bound(cost, 1, 1 ether);
        extraValue = bound(extraValue, 1, 1 ether);

        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));
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

        // update mock bridger config
        bridger.setRecipient(address(childGauge));
        bridger.setCost(cost);

        // claim rewards every week
        // every time `childFactory.mint` is called the rewards
        // are fully distributed after the current week ends
        // thus we need to wait one more week
        for (uint256 i = 0; i < numWeeksWait + 1; i++) {
            skip(1 weeks);
            deal(address(this), address(this).balance + cost + extraValue);
            uint256 beforeBalance = address(this).balance;
            rootFactory.transmit_emissions{value: cost + extraValue}(address(rootGauge));
            assertEq(beforeBalance - address(this).balance, cost, "didn't get refund");
            childFactory.mint(address(childGauge));
        }

        // check balance
        uint256 expectedAmount = tokenAdmin.INITIAL_RATE() * (numWeeksWait - 1) * (1 weeks); // first week has no rewards
        assertApproxEqRel(mockToken.balanceOf(address(this)), expectedAmount, 1e12, "balance incorrect");
    }

    function test_gauge_stakeRewards_bridgerCost_multipleGauges(
        uint256 numWeeksWait,
        uint256 cost,
        uint256 numGauges,
        uint256 extraValue
    ) external {
        numWeeksWait = bound(numWeeksWait, 1, 50);
        cost = bound(cost, 1, 1 ether);
        numGauges = bound(numGauges, 1, 10);
        extraValue = bound(extraValue, 1, 1 ether);

        // create gauge
        IRootGauge[] memory rootGaugeList = new IRootGauge[](numGauges);
        IChildGauge[] memory childGaugeList = new IChildGauge[](numGauges);
        BunniKey[] memory keyList = new BunniKey[](numGauges);
        for (uint256 i; i < numGauges; i++) {
            BunniKey memory _key = BunniKey({
                pool: pool,
                tickLower: TICK_LOWER - int24(uint24(i + 1)) * pool.tickSpacing(),
                tickUpper: TICK_UPPER + int24(uint24(i + 1)) * pool.tickSpacing()
            });
            keyList[i] = _key;
            bunniHub.deployBunniToken(_key);
            tokenA.mint(address(this), 1e18);
            tokenB.mint(address(this), 1e18);
            bunniHub.deposit(
                IBunniHub.DepositParams({
                    key: _key,
                    amount0Desired: 1e18,
                    amount1Desired: 1e18,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp,
                    recipient: address(this)
                })
            );
            IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, _key, 1e18));
            rootGaugeList[i] = rootGauge;
            childGaugeList[i] = IChildGauge(childFactory.deploy_gauge(_key));

            // approve gauge
            vm.prank(gaugeControllerAdmin);
            gaugeController.add_gauge(address(rootGauge), 0, 1);
        }

        // lock tokens in voting escrow
        mockToken.mint(address(this), 1 ether);
        mockToken.approve(address(votingEscrow), type(uint256).max);
        votingEscrow.create_lock(1 ether, block.timestamp + 200 weeks);

        // push vetoken balance from beacon to recipient
        beacon.broadcastVeBalance(address(this), 0, 0, 0);

        for (uint256 i; i < numGauges; i++) {
            // stake liquidity in child gauge
            BunniKey memory _key = keyList[i];
            IChildGauge childGauge = childGaugeList[i];

            IBunniToken bunniToken = bunniHub.getBunniToken(_key);
            bunniToken.approve(address(childGauge), type(uint256).max);
            uint256 amount = bunniToken.balanceOf(address(this));
            childGauge.deposit(amount);

            bridger.setRecipientOfSender(address(rootGaugeList[i]), address(childGauge));
        }

        // update mock bridger config
        bridger.setCost(cost);

        // claim rewards every week
        // every time `childFactory.mint` is called the rewards
        // are fully distributed after the current week ends
        // thus we need to wait one more week
        for (uint256 i = 0; i < numWeeksWait + 1; i++) {
            skip(1 weeks);
            deal(address(this), address(this).balance + cost * numGauges + extraValue);
            address[] memory rootGaugeAddressList;
            address[] memory childGaugeAddressList;
            assembly {
                rootGaugeAddressList := rootGaugeList
                childGaugeAddressList := childGaugeList
            }
            uint256 beforeBalance = address(this).balance;
            rootFactory.transmit_emissions_multiple{value: cost * numGauges + extraValue}(rootGaugeAddressList);
            assertEq(beforeBalance - address(this).balance, cost * numGauges, "didn't get refund");
            childFactory.mint_many(childGaugeAddressList);
        }

        // check balance
        uint256 expectedAmount = tokenAdmin.INITIAL_RATE() * (numWeeksWait - 1) * (1 weeks); // first week has no rewards
        assertApproxEqRel(mockToken.balanceOf(address(this)), expectedAmount, 1e12, "balance incorrect");
    }

    function test_gauge_stakeAndUnstake() external {
        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));
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

    function test_gauge_stakeRewards_capped(uint256 numWeeksWait, uint256 weightCap) external {
        weightCap = bound(weightCap, 1e15, 1e18);
        numWeeksWait = bound(numWeeksWait, 1, 50);

        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, weightCap));
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
        uint256 expectedAmount = tokenAdmin.INITIAL_RATE() * (numWeeksWait - 1) * (1 weeks) * weightCap / 1e18; // first week has no rewards
        assertApproxEqRel(mockToken.balanceOf(address(this)), expectedAmount, 1e12, "balance incorrect");
    }

    function test_gauge_stakeRewards_setCap(uint256 numWeeksWait, uint256 weightCap) external {
        weightCap = bound(weightCap, 1e15, 1e18);
        numWeeksWait = bound(numWeeksWait, 1, 50);

        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));
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

        // update gauge cap
        rootGauge.setRelativeWeightCap(weightCap);

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
        uint256 expectedAmount = tokenAdmin.INITIAL_RATE() * (numWeeksWait - 1) * (1 weeks) * weightCap / 1e18; // first week has no rewards
        assertApproxEqRel(mockToken.balanceOf(address(this)), expectedAmount, 1e12, "balance incorrect");
    }

    function test_kickAfterTokenlessProductionChange() public {
        // address(this) starts with a working balance of 0.2b + 0.9(v/V)B = 0.2 * 0.7B + 0.9 * 0.5B = 0.59B
        // and has 0.1b + 0.8(v/V)B = 0.1 * 0.7B + 0.8 * 0.5B = 0.47B after tokenless_production is set to 10
        // which means it has an incentive to abuse the previous boost meaning it should be kicked
        // in general, kicking should happen when:
        // - tokenless_production is decreased (i.e. max boost is increased)
        // - v/V < b/B (i.e. the user doesn't have enough vetokens to achieve max boost)
        // derivation:
        // we want the following inequalities to be true
        // - t_0 * b + (1-t_0)(v/V)B > t_1 * b + (1-t_1)(v/V)B (working balance might decrease after update) => (t_0 - t_1)(v/V) < (t_0 - t_1)(b/B)
        // - t_0 * b + (1-t_0)(v/V)B < b (working balance not bounded by stake balance) => v/V < b/B
        // - t_1 * b + (1-t_1)(v/V)B < b (working balance not bounded by stake balance) => v/V < b/B
        // which is equivalent to:
        // - t_0 > t_1 (tokenless_production is decreased)
        // - v/V < b/B (not at max boost)

        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        // approve gauge
        vm.prank(gaugeControllerAdmin);
        gaugeController.add_gauge(address(rootGauge), 0, 1);

        // init tokenless production
        childGauge.set_tokenless_production(20);

        // lock tokens in voting escrow
        mockToken.mint(address(this), 1 ether);
        mockToken.approve(address(votingEscrow), type(uint256).max);
        votingEscrow.create_lock(1 ether, block.timestamp + 200 weeks);

        // lock for another user
        address tester = makeAddr("tester");
        vm.prank(smartWalletCheckerOwner);
        smartWalletChecker.allowlistAddress(tester);
        vm.startPrank(tester);
        mockToken.mint(tester, 1 ether);
        mockToken.approve(address(votingEscrow), type(uint256).max);
        votingEscrow.create_lock(1 ether, block.timestamp + 200 weeks);
        vm.stopPrank();

        // push vetoken balance from beacon to recipient
        beacon.broadcastVeBalance(address(this), 0, 0, 0);
        beacon.broadcastVeBalance(tester, 0, 0, 0);

        // stake liquidity in child gauge for both this and tester
        IBunniToken bunniToken = bunniHub.getBunniToken(key);
        bunniToken.transfer(tester, bunniToken.balanceOf(address(this)) * 3 / 10);

        vm.startPrank(tester);
        bunniToken.approve(address(childGauge), type(uint256).max);
        childGauge.deposit(bunniToken.balanceOf(tester));
        vm.stopPrank();

        bunniToken.approve(address(childGauge), type(uint256).max);
        childGauge.deposit(bunniToken.balanceOf(address(this)));

        // cannot kick at this point
        vm.expectRevert();
        childGauge.kick(address(this));

        // update tokenless production
        childGauge.set_tokenless_production(10);

        // can kick address(this)
        uint256 beforeWorkingBalance = childGauge.working_balances(address(this));
        childGauge.kick(address(this));
        assertLt(
            childGauge.working_balances(address(this)),
            beforeWorkingBalance,
            "working balance didn't change after kicking"
        );
    }

    /**
     * Gauge creation/kill tests
     */

    function test_createGauge() external {
        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        // verify gauge state
        assertEq(rootGauge.is_killed(), false, "Root gauge killed at creation");
        assertEq(childGauge.is_killed(), false, "Child gauge killed at creation");
    }

    function test_killOutOfRangeGauge() external {
        // create new position to initialize tickLower in the pool
        int24 tickLower = 100;
        int24 tickUpper = 1000;
        tokenA.mint(address(this), 1e18);
        tokenB.mint(address(this), 1e18);
        BunniKey memory k = BunniKey({pool: pool, tickLower: tickLower, tickUpper: tickUpper});
        bunniHub.deployBunniToken(k);
        bunniHub.deposit(
            IBunniHub.DepositParams({
                key: k,
                amount0Desired: 1e18,
                amount1Desired: 1e18,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp,
                recipient: address(this)
            })
        );

        // create gauge
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(k));

        // record
        oracle.startRecording(address(pool), 100, tickUpper);
        skip(RECORDING_MIN_LENGTH);
        UniswapPoorOracle.PositionState state = oracle.finishRecording(address(pool), 100, tickUpper);
        assertEq(uint256(state), uint256(UniswapPoorOracle.PositionState.OUT_OF_RANGE), "State not OUT_OF_RANGE");

        // verify gauge state
        assertEq(childGauge.is_killed(), true, "Out-of-range gauge hasn't been killed");
    }

    function test_reviveInRangeGauge() external {
        // create gauge
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        // make swap to move the price out of range
        uint256 amountIn = 1e20;
        tokenA.mint(address(this), amountIn);
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            fee: FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        router.exactInputSingle(swapParams);
        (, int24 tick,,,,,) = pool.slot0();
        assert(tick > TICK_UPPER || tick < TICK_LOWER);

        // record
        oracle.startRecording(address(pool), TICK_LOWER, TICK_UPPER);
        skip(RECORDING_MIN_LENGTH);
        UniswapPoorOracle.PositionState state = oracle.finishRecording(address(pool), TICK_LOWER, TICK_UPPER);
        assertEq(uint256(state), uint256(UniswapPoorOracle.PositionState.OUT_OF_RANGE), "State not OUT_OF_RANGE");

        // verify gauge state
        assertEq(childGauge.is_killed(), true, "Out-of-range gauge hasn't been killed");

        // make swap to move the price back into range
        swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(tokenB),
            tokenOut: address(tokenA),
            fee: FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: tokenB.balanceOf(address(this)),
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        router.exactInputSingle(swapParams);
        (, tick,,,,,) = pool.slot0();
        assert(tick <= TICK_UPPER && tick >= TICK_LOWER);

        // record
        oracle.startRecording(address(pool), TICK_LOWER, TICK_UPPER);
        skip(RECORDING_MIN_LENGTH);
        state = oracle.finishRecording(address(pool), TICK_LOWER, TICK_UPPER);
        assertEq(uint256(state), uint256(UniswapPoorOracle.PositionState.IN_RANGE), "State not IN_RANGE");

        // verify gauge state
        assertEq(childGauge.is_killed(), false, "In-range gauge hasn't been revived");
    }

    function test_adminKillGauge() external {
        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        // kill gauge
        rootGauge.set_killed(true);
        childGauge.killGauge();

        // verify gauge state
        assertEq(rootGauge.is_killed(), true, "Root gauge hasn't been killed");
        assertEq(childGauge.is_killed(), true, "Child gauge hasn't been killed");
    }

    function test_adminUnkillKilledGauge(uint256 numWeeksWait) external {
        numWeeksWait = bound(numWeeksWait, 1, 50);

        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        // approve gauge
        vm.prank(gaugeControllerAdmin);
        gaugeController.add_gauge(address(rootGauge), 0, 1);
        bridger.setRecipient(address(childGauge));

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

        // kill gauge
        rootGauge.set_killed(true);
        childGauge.killGauge();

        // wait
        skip(numWeeksWait * 1 weeks);

        // unkill gauge
        rootGauge.set_killed(false);
        childGauge.unkillGauge();

        // claim rewards
        rootFactory.transmit_emissions(address(rootGauge));
        childFactory.mint(address(childGauge));

        // claim rewards in the next epoch
        skip(1 weeks);
        rootFactory.transmit_emissions(address(rootGauge));
        childFactory.mint(address(childGauge));

        // verify gauge state
        assertEq(rootGauge.is_killed(), false, "Root gauge hasn't been unkilled");
        assertEq(childGauge.is_killed(), false, "Child gauge hasn't been unkilled");

        // check balance
        assertEq(mockToken.balanceOf(address(this)), 0, "received rewards while gauge was killed");
    }

    function test_adminUnkillOutOfRangeGauge() external {
        // create gauge
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        // make swap to move the price out of range
        uint256 amountIn = 1e20;
        tokenA.mint(address(this), amountIn);
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            fee: FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        router.exactInputSingle(swapParams);
        (, int24 tick,,,,,) = pool.slot0();
        assert(tick > TICK_UPPER || tick < TICK_LOWER);

        // record
        oracle.startRecording(address(pool), TICK_LOWER, TICK_UPPER);
        skip(RECORDING_MIN_LENGTH);
        UniswapPoorOracle.PositionState state = oracle.finishRecording(address(pool), TICK_LOWER, TICK_UPPER);
        assertEq(uint256(state), uint256(UniswapPoorOracle.PositionState.OUT_OF_RANGE), "State not OUT_OF_RANGE");

        // verify gauge state
        assertEq(childGauge.is_killed(), true, "Out-of-range gauge hasn't been killed");

        // admin unkill gauge
        childGauge.unkillGauge();

        // verify gauge state
        assertEq(childGauge.is_killed(), false, "Gauge hasn't been unkilled");
    }

    /**
     * Contract ownership tests
     */

    function test_ownership_rootGaugeFactory() external {
        address newOwner = makeAddr("newOwner");

        // transfer ownership
        rootFactory.commit_transfer_ownership(newOwner);
        assertEq(rootFactory.owner(), address(this), "commit_transfer_ownership updated admin");

        // claim ownership
        vm.prank(newOwner);
        rootFactory.accept_transfer_ownership();
        assertEq(rootFactory.owner(), newOwner, "accept_transfer_ownership didn't update admin");
    }

    function test_ownership_rootGaugeFactory_randoCannotChangePendingAdmin(address rando) external {
        vm.assume(rando != address(this));

        address newOwner = makeAddr("newOwner");

        // transfer ownership
        vm.prank(rando);
        vm.expectRevert();
        rootFactory.commit_transfer_ownership(newOwner);
    }

    function test_ownership_rootGaugeFactory_randoCannotClaimAdmin(address rando) external {
        address newOwner = makeAddr("newOwner");
        vm.assume(rando != newOwner);

        // transfer ownership
        rootFactory.commit_transfer_ownership(newOwner);

        // claim ownership
        vm.prank(rando);
        vm.expectRevert();
        rootFactory.accept_transfer_ownership();
    }

    function test_ownership_childGaugeFactory() external {
        address newOwner = makeAddr("newOwner");

        // transfer ownership
        childFactory.commit_transfer_ownership(newOwner);
        assertEq(childFactory.owner(), address(this), "commit_transfer_ownership updated admin");

        // claim ownership
        vm.prank(newOwner);
        childFactory.accept_transfer_ownership();
        assertEq(childFactory.owner(), newOwner, "accept_transfer_ownership didn't update admin");
    }

    function test_ownership_childGaugeFactory_randoCannotChangePendingAdmin(address rando) external {
        vm.assume(rando != address(this));

        address newOwner = makeAddr("newOwner");

        // transfer ownership
        vm.prank(rando);
        vm.expectRevert();
        childFactory.commit_transfer_ownership(newOwner);
    }

    function test_ownership_childGaugeFactory_randoCannotClaimAdmin(address rando) external {
        address newOwner = makeAddr("newOwner");
        vm.assume(rando != newOwner);

        // transfer ownership
        childFactory.commit_transfer_ownership(newOwner);

        // claim ownership
        vm.prank(rando);
        vm.expectRevert();
        childFactory.accept_transfer_ownership();
    }

    function test_rootGauge_randoCannotSetRelativeWeightCap(address rando, uint256 weightCap) external {
        vm.assume(rando != address(this));

        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));

        // set cap
        vm.prank(rando);
        vm.expectRevert();
        rootGauge.setRelativeWeightCap(weightCap);
    }

    function test_rootGauge_relativeWeightCapCannotExceedMax(uint256 weightCap) external {
        vm.assume(weightCap > 1e18);

        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));

        // set cap
        vm.expectRevert();
        rootGauge.setRelativeWeightCap(weightCap);
    }

    function test_rootGauge_updateBridger(address newBridger) external {
        vm.assume(newBridger != address(bridger));

        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));

        // update bridger in factory
        rootFactory.set_bridger(block.chainid, newBridger);

        // update bridger in gauge
        rootGauge.update_bridger();

        // verify new bridger
        assertEq(rootGauge.bridger(), newBridger, "didn't set new bridger in gauge");
        assertEq(mockToken.allowance(address(rootGauge), address(bridger)), 0, "didn't reset approval to old bridger");
        assertEq(
            mockToken.allowance(address(rootGauge), newBridger), type(uint256).max, "didn't set approval to new bridger"
        );
    }

    function test_childGaugeFactory_updateToken(uint256 numWeeksWait) external {
        // verify token
        assertEq(childFactory.token(), address(mockToken), "childFactory has wrong initial token address");

        // update token
        TestERC20Mintable newToken = new TestERC20Mintable();
        childFactory.set_token(address(newToken));

        // verify token
        assertEq(childFactory.token(), address(newToken), "childFactory has wrong updated token address");

        // test rewards
        numWeeksWait = bound(numWeeksWait, 1, 50);
        bridger.setBridgedToken(newToken);
        newToken.mint(address(bridger), 1e36);

        // create gauge
        IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, key, 1e18));
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
        assertApproxEqRel(newToken.balanceOf(address(this)), expectedAmount, 1e12, "balance incorrect");
    }

    function test_childGaugeFactory_updateToken_cannotBeCalledByRando(address rando, address newToken) external {
        vm.assume(rando != address(this));
        vm.prank(rando);
        vm.expectRevert();
        childFactory.set_token(newToken);
    }

    function test_childGaugeFactory_rescueToken(uint256 amount, address recipient) external {
        vm.assume(address(childFactory) != recipient);

        TestERC20Mintable stuckToken = new TestERC20Mintable();
        stuckToken.mint(address(childFactory), amount);
        assertEq(stuckToken.balanceOf(address(childFactory)), amount);

        childFactory.rescue_token(address(stuckToken), recipient);
        assertEq(stuckToken.balanceOf(address(childFactory)), 0);
        assertEq(stuckToken.balanceOf(recipient), amount);
    }

    function test_childGaugeFactory_rescueToken_cannotBeCalledByRando(address rando, uint256 amount, address recipient)
        external
    {
        vm.assume(rando != address(this));

        TestERC20Mintable stuckToken = new TestERC20Mintable();
        stuckToken.mint(address(childFactory), amount);

        vm.prank(rando);
        vm.expectRevert();
        childFactory.rescue_token(address(stuckToken), recipient);
    }

    function test_childGaugeFactory_rescueToken_cannotStealTokens(uint256 amount, address recipient) external {
        mockToken.mint(address(childFactory), amount);

        vm.expectRevert();
        childFactory.rescue_token(address(mockToken), recipient);
    }

    function test_childGauge_rescueToken(uint256 amount, address recipient) external {
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        vm.assume(address(childGauge) != recipient);

        TestERC20Mintable stuckToken = new TestERC20Mintable();
        stuckToken.mint(address(childGauge), amount);
        assertEq(stuckToken.balanceOf(address(childGauge)), amount);

        childGauge.rescue_token(address(stuckToken), recipient);
        assertEq(stuckToken.balanceOf(address(childGauge)), 0);
        assertEq(stuckToken.balanceOf(recipient), amount);
    }

    function test_childGauge_rescueToken_cannotBeCalledByRando(address rando, uint256 amount, address recipient)
        external
    {
        vm.assume(rando != address(this));

        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));
        TestERC20Mintable stuckToken = new TestERC20Mintable();
        stuckToken.mint(address(childGauge), amount);

        vm.prank(rando);
        vm.expectRevert();
        childGauge.rescue_token(address(stuckToken), recipient);
    }

    function test_childGauge_rescueToken_cannotStealTokens(uint256 amount, address recipient) external {
        IChildGauge childGauge = IChildGauge(childFactory.deploy_gauge(key));

        // cannot steal core reward token
        mockToken.mint(address(childGauge), amount);
        vm.expectRevert();
        childGauge.rescue_token(address(mockToken), recipient);

        // cannot steal LP token
        IBunniToken bunniToken = bunniHub.getBunniToken(key);
        deal(address(bunniToken), address(childGauge), amount);
        vm.expectRevert();
        childGauge.rescue_token(address(bunniToken), recipient);

        // cannot steal custom reward token
        TestERC20Mintable stuckToken = new TestERC20Mintable();
        childGauge.add_reward(address(stuckToken), address(this));
        stuckToken.mint(address(childGauge), amount);
        vm.expectRevert();
        childGauge.rescue_token(address(stuckToken), recipient);
    }

    /**
     * Automation tests
     */
    function test_transmitter_transmitMultiple(uint256 cost, uint256 numGauges) external {
        cost = bound(cost, 1, 1 ether);
        numGauges = bound(numGauges, 1, 10);

        // warp to before next epoch
        uint256 epoch = block.timestamp / (1 weeks);
        uint256 nextEpochStart = (epoch + 1) * (1 weeks);
        vm.warp(nextEpochStart - 1 hours);

        // update mock bridger config
        bridger.setCost(cost);

        // create gauges
        IRootGauge[] memory rootGaugeList = new IRootGauge[](numGauges);
        IChildGauge[] memory childGaugeList = new IChildGauge[](numGauges);
        BunniKey[] memory keyList = new BunniKey[](numGauges);
        for (uint256 i; i < numGauges; i++) {
            BunniKey memory _key = BunniKey({
                pool: pool,
                tickLower: TICK_LOWER - int24(uint24(i + 1)) * pool.tickSpacing(),
                tickUpper: TICK_UPPER + int24(uint24(i + 1)) * pool.tickSpacing()
            });
            keyList[i] = _key;
            bunniHub.deployBunniToken(_key);
            tokenA.mint(address(this), 1e18);
            tokenB.mint(address(this), 1e18);
            bunniHub.deposit(
                IBunniHub.DepositParams({
                    key: _key,
                    amount0Desired: 1e18,
                    amount1Desired: 1e18,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp,
                    recipient: address(this)
                })
            );
            IRootGauge rootGauge = IRootGauge(rootFactory.deploy_gauge(block.chainid, _key, 1e18));
            rootGaugeList[i] = rootGauge;
            childGaugeList[i] = IChildGauge(childFactory.deploy_gauge(_key));

            // approve gauge
            vm.prank(gaugeControllerAdmin);
            gaugeController.add_gauge(address(rootGauge), 0, 1);
        }

        // send ETH to transmitter
        payable(address(transmitter)).transfer(cost * numGauges);

        // exec
        (bool canExec, bytes memory execPayload) = transmitter.checker();
        assertEq(canExec, true, "cannot exec");
        address[] memory gaugeList;
        assembly {
            gaugeList := rootGaugeList
        }
        assertEq(
            execPayload, abi.encodeCall(CrosschainRewardTransmitter.transmitMultiple, (gaugeList, cost * numGauges))
        );
        (bool success,) = address(transmitter).call(execPayload);
        assertEq(success, true, "exec unsuccessful");
        assertEq(address(transmitter).balance, 0, "transmitter still has balance");
    }

    receive() external payable {}

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
