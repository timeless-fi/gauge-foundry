// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "bunni/BunniHub.sol";

import {Minter} from "../src/Minter.sol";
import {TokenAdmin} from "../src/TokenAdmin.sol";
import {CREATE3Script} from "./base/CREATE3Script.sol";
import {VyperDeployer} from "../src/lib/VyperDeployer.sol";
import {SmartWalletChecker} from "../src/SmartWalletChecker.sol";
import {IVotingEscrow} from "../src/interfaces/IVotingEscrow.sol";
import {IERC20Mintable} from "../src/interfaces/IERC20Mintable.sol";
import {ILiquidityGauge} from "../src/interfaces/ILiquidityGauge.sol";
import {IGaugeController} from "../src/interfaces/IGaugeController.sol";
import {TimelessLiquidityGaugeFactory} from "../src/TimelessLiquidityGaugeFactory.sol";

contract DeployScript is CREATE3Script("1.0.0"), VyperDeployer {
    function run()
        public
        returns (
            Minter minter,
            TokenAdmin tokenAdmin,
            IVotingEscrow votingEscrow,
            IGaugeController gaugeController,
            TimelessLiquidityGaugeFactory factory,
            SmartWalletChecker smartWalletChecker
        )
    {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        address admin = vm.envAddress("ADMIN");

        {
            IERC20Mintable rewardToken = IERC20Mintable(getCreate3Contract("OptionsToken"));
            tokenAdmin = TokenAdmin(
                create3.deploy(
                    getCreate3ContractSalt("TokenAdmin"),
                    bytes.concat(type(TokenAdmin).creationCode, abi.encode(rewardToken, admin))
                )
            );
        }
        {
            address lockToken = vm.envAddress("LOCK_TOKEN");
            votingEscrow = IVotingEscrow(
                create3.deploy(
                    getCreate3ContractSalt("VotingEscrow"),
                    bytes.concat(
                        compileContract("VotingEscrow"), abi.encode(lockToken, "Timeless Voting Escrow", "veTIT", admin)
                    )
                )
            );
        }
        gaugeController = IGaugeController(
            create3.deploy(
                getCreate3ContractSalt("GaugeController"),
                bytes.concat(compileContract("GaugeController"), abi.encode(votingEscrow, admin))
            )
        );
        minter = Minter(
            create3.deploy(
                getCreate3ContractSalt("Minter"),
                bytes.concat(type(Minter).creationCode, abi.encode(tokenAdmin, gaugeController))
            )
        );
        address veDelegation = create3.deploy(
            getCreate3ContractSalt("VotingEscrowDelegation"),
            bytes.concat(
                compileContract("VotingEscrowDelegation"),
                abi.encode(votingEscrow, "Timeless VE-Delegation", "veTIT-BOOST", "", admin)
            )
        );
        ILiquidityGauge liquidityGaugeTemplate = ILiquidityGauge(
            create3.deploy(
                getCreate3ContractSalt("TimelessLiquidityGauge"),
                bytes.concat(compileContract("TimelessLiquidityGauge"), abi.encode(minter))
            )
        );
        {
            BunniHub bunniHub = BunniHub(vm.envAddress("BUNNI_HUB"));
            factory = TimelessLiquidityGaugeFactory(
                create3.deploy(
                    getCreate3ContractSalt("TimelessLiquidityGaugeFactory"),
                    bytes.concat(
                        type(TimelessLiquidityGaugeFactory).creationCode,
                        abi.encode(liquidityGaugeTemplate, admin, veDelegation, bunniHub)
                    )
                )
            );
        }
        {
            address[] memory initialAllowlist = vm.envAddress("INITIAL_ALLOWLIST", ",");
            smartWalletChecker = SmartWalletChecker(
                create3.deploy(
                    getCreate3ContractSalt("SmartWalletChecker"),
                    bytes.concat(type(SmartWalletChecker).creationCode, abi.encode(admin, initialAllowlist))
                )
            );
        }

        // NOTE: The admin still needs to
        // - Activate inflation in tokenAdmin
        // - Add smart wallet checker to votingEscrow

        vm.stopBroadcast();
    }
}
