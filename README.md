# Timeless gauge contracts

Foundry repo for contracts used by Timeless's gauge system.

## Installation

To install with [Foundry](https://github.com/gakonst/foundry):

```
forge install timeless-fi/gauge-foundry
```

## Local development

This project uses [Foundry](https://github.com/gakonst/foundry) as the development framework. It also requires Vyper to be installed.

### Dependencies

```
forge install
```

### Compilation

```
forge build
```

### Testing

```
forge test
```

### Contract deployment

Please create a `.env` file before deployment. An example can be found in `.env.example`.

#### Dryrun

```
forge script script/Deploy.s.sol -f [network]
```

### Live

```
forge script script/Deploy.s.sol -f [network] --verify --broadcast
```

## Known issues

### Gauge stakers can abuse their boost after `tokenless_production` is updated

After the `tokenless_production` value has been updated in `TimelessLiquidityGauge`, some stakers may see their staking weight decrease once `_update_liquidity_limit()` is called, but this may not happen if the staker doesn't call the gauge contract (e.g. deposit, withdraw, claim rewards), which gives them outsized staking weights.