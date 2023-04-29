// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRootGauge {
    function transmit_emissions() external;
    function integrate_fraction(address _user) external returns (uint256);
    function update_bridger() external;
    function initialize(address _bridger, uint256 _chain_id) external;
    function chain_id() external view returns (uint256);
    function is_killed() external view returns (bool);
    function bridger() external view returns (address);
    function factory() external view returns (address);
    function inflation_params() external view returns (uint256 rate, uint256 finish_time);
    function last_period() external view returns (uint256);
    function total_emissions() external view returns (uint256);
    function set_killed(bool killed) external;
    function setRelativeWeightCap(uint256 relativeWeightCap) external;
    function getRelativeWeightCap() external view returns (uint256);
    function getCappedRelativeWeight(uint256 time) external view returns (uint256);
}
