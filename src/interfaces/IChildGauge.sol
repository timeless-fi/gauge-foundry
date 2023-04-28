// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IChildGauge {
    function approve(address _spender, uint256 _value) external returns (bool);
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (bool);
    function decreaseAllowance(address _spender, uint256 _subtracted_value) external returns (bool);
    function user_checkpoint(address addr) external returns (bool);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function tokenless_production() external view returns (uint8);
    function gauge_state() external view returns (uint8);
    function lp_token() external view returns (address);
    function manager() external view returns (address);
    function position_key() external view returns (bytes32);
    function totalSupply() external view returns (uint256);
    function working_supply() external view returns (uint256);
    function period() external view returns (uint256);
    function reward_count() external view returns (uint256);
    function nonces(address user) external view returns (uint256);
    function balanceOf(address user) external view returns (uint256);
    function working_balances(address user) external view returns (uint256);
    function period_timestamp(uint256 epoch) external view returns (uint256);
    function integrate_checkpoint_of(address user) external view returns (uint256);
    function integrate_fraction(address user) external view returns (uint256);
    function integrate_inv_supply(uint256 epoch) external view returns (uint256);
    function integrate_inv_supply_of(address user) external view returns (uint256);
    function reward_data()
        external
        view
        returns (address distributor, uint256 period_finish, uint256 rate, uint256 last_update, uint256 integral);
    function rewards_receiver() external view returns (address);
    function inflation_rate() external view returns (uint256);
    function deposit(uint256 amount) external;
    function deposit(uint256 amount, address recipient) external;
    function withdraw(uint256 amount) external;
    function claim_rewards() external;
    function is_killed() external view returns (bool);
    function killGauge() external;
    function unkillGauge() external;
}
