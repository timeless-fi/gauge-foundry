// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "bunni/src/interfaces/IBunniHub.sol";

interface IRootGaugeFactory {
    function transmit_emissions(address _gauge) external;
    function deploy_gauge(uint256 _chain_id, BunniKey calldata _key, uint256 _relative_weight_cap)
        external
        returns (address);
    function set_bridger(uint256 _chain_id, address _bridger) external;
    function set_implementation(address _implementation) external;
    function commit_transfer_ownership(address _future_owner) external;
    function accept_transfer_ownership() external;
    function get_implementation() external view returns (address);
    function owner() external view returns (address);
    function future_owner() external view returns (address);
    function get_bridger() external view returns (address);
    function get_gauge_count() external view returns (uint256);
    function is_valid_gauge() external view returns (bool);
}
