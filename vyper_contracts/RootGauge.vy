# @version 0.3.7
"""
@title Root Liquidity Gauge Implementation
@license MIT
@author Curve Finance
"""


interface Bridger:
    def cost() -> uint256: view
    def bridge(_token: address, _destination: address, _amount: uint256): payable

interface TokenAdmin:
    def start_epoch_time_write() -> uint256: nonpayable
    def future_epoch_time_write() -> uint256: nonpayable
    def rate() -> uint256: view

interface ERC20:
    def balanceOf(_account: address) -> uint256: view
    def approve(_account: address, _value: uint256): nonpayable
    def transfer(_to: address, _amount: uint256): nonpayable

interface GaugeController:
    def checkpoint_gauge(addr: address): nonpayable
    def gauge_relative_weight(addr: address, time: uint256) -> uint256: view

interface Factory:
    def get_bridger(_chain_id: uint256) -> address: view
    def owner() -> address: view

interface Minter:
    def mint(_gauge: address): nonpayable
    def getToken() -> address: view
    def getTokenAdmin() -> address: view
    def getGaugeController() -> address: view


event RelativeWeightCapChanged:
    new_relative_weight_cap: uint256

event SetKilled:
    is_killed: bool


struct InflationParams:
    rate: uint256
    finish_time: uint256


MAX_RELATIVE_WEIGHT_CAP: constant(uint256) = 10 ** 18
WEEK: constant(uint256) = 604800
YEAR: constant(uint256) = 86400 * 365
RATE_DENOMINATOR: constant(uint256) = 10 ** 18
RATE_REDUCTION_COEFFICIENT: constant(uint256) = 1189207115002721024  # 2 ** (1/4) * 1e18
RATE_REDUCTION_TIME: constant(uint256) = YEAR

TOKEN: immutable(address)
GAUGE_CONTROLLER: immutable(address)
MINTER: immutable(address)
TOKEN_ADMIN: immutable(address)


chain_id: public(uint256)
is_killed: public(bool)
bridger: public(address)
factory: public(address)
inflation_params: public(InflationParams)

last_period: public(uint256)
total_emissions: public(uint256)

_relative_weight_cap: uint256

@external
def __init__(_minter: address):
    self.factory = 0x000000000000000000000000000000000000dEaD

    # assign immutable variables
    TOKEN = Minter(_minter).getToken()
    TOKEN_ADMIN = Minter(_minter).getTokenAdmin()
    GAUGE_CONTROLLER = Minter(_minter).getGaugeController()
    MINTER = _minter


@payable
@external
def transmit_emissions():
    """
    @notice Mint any new emissions and transmit across to child gauge
    """
    assert msg.sender == self.factory  # dev: call via factory

    Minter(MINTER).mint(self)
    minted: uint256 = ERC20(TOKEN).balanceOf(self)

    if minted != 0:
        bridger: address = self.bridger
        Bridger(bridger).bridge(TOKEN, self, minted, value=msg.value)


@view
@external
def integrate_fraction(_user: address) -> uint256:
    """
    @notice Query the total emissions `_user` is entitled to
    @dev Any value of `_user` other than the gauge address will return 0
    """
    if _user == self:
        return self.total_emissions
    return 0


@external
def user_checkpoint(_user: address) -> bool:
    """
    @notice Checkpoint the gauge updating total emissions
    @param _user Vestigal parameter with no impact on the function
    """
    # the last period we calculated emissions up to (but not including)
    last_period: uint256 = self.last_period
    # our current period (which we will calculate emissions up to)
    current_period: uint256 = block.timestamp / WEEK

    # only checkpoint if the current period is greater than the last period
    # last period is always less than or equal to current period and we only calculate
    # emissions up to current period (not including it)
    if last_period != current_period:
        # checkpoint the gauge filling in any missing weight data
        GaugeController(GAUGE_CONTROLLER).checkpoint_gauge(self)

        params: InflationParams = self.inflation_params
        emissions: uint256 = 0

        # only calculate emissions for at most 256 periods since the last checkpoint
        for i in range(last_period, last_period + 256):
            if i == current_period:
                # don't calculate emissions for the current period
                break
            period_time: uint256 = i * WEEK
            weight: uint256 = self._getCappedRelativeWeight(period_time)

            if period_time <= params.finish_time and params.finish_time < period_time + WEEK:
                # calculate with old rate
                emissions += weight * params.rate * (params.finish_time - period_time) / 10 ** 18
                # update rate
                params.rate = params.rate * RATE_DENOMINATOR / RATE_REDUCTION_COEFFICIENT
                # calculate with new rate
                emissions += weight * params.rate * (period_time + WEEK - params.finish_time) / 10 ** 18
                # update finish time
                params.finish_time += RATE_REDUCTION_TIME
                # update storage
                self.inflation_params = params
            else:
                emissions += weight * params.rate * WEEK / 10 ** 18

        self.last_period = current_period
        self.total_emissions += emissions

    return True


@external
def set_killed(_is_killed: bool):
    """
    @notice Set the gauge kill status
    @dev Inflation params are modified accordingly to disable/enable emissions
    """
    assert msg.sender == Factory(self.factory).owner()

    if _is_killed:
        self.inflation_params.rate = 0
    else:
        self.inflation_params = InflationParams({
            rate: TokenAdmin(TOKEN_ADMIN).rate(),
            finish_time: TokenAdmin(TOKEN_ADMIN).future_epoch_time_write()
        })
        self.last_period = block.timestamp / WEEK
    self.is_killed = _is_killed

    log SetKilled(_is_killed)


@external
def update_bridger():
    """
    @notice Update the bridger used by this contract
    @dev Bridger contracts should prevent briding if ever updated
    """
    # reset approval
    bridger: address = Factory(self.factory).get_bridger(self.chain_id)
    ERC20(TOKEN).approve(self.bridger, 0)
    ERC20(TOKEN).approve(bridger, max_value(uint256))
    self.bridger = bridger


@external
def setRelativeWeightCap(relative_weight_cap: uint256):
    """
    @notice Sets a new relative weight cap for the gauge.
            The value shall be normalized to 1e18, and not greater than MAX_RELATIVE_WEIGHT_CAP.
    @param relative_weight_cap New relative weight cap.
    """
    assert msg.sender == Factory(self.factory).owner()  # dev: only owner
    self._setRelativeWeightCap(relative_weight_cap)


@external
@view
def getRelativeWeightCap() -> uint256:
    """
    @notice Returns relative weight cap for the gauge.
    """
    return self._relative_weight_cap


@external
@view
def getCappedRelativeWeight(time: uint256) -> uint256:
    """
    @notice Returns the gauge's relative weight for a given time, capped to its _relative_weight_cap attribute.
    @param time Timestamp in the past or present.
    """
    return self._getCappedRelativeWeight(time)


@external
@pure
def getMaxRelativeWeightCap() -> uint256:
    """
    @notice Returns the maximum value that can be set to _relative_weight_cap attribute.
    """
    return MAX_RELATIVE_WEIGHT_CAP


@internal
@view
def _getCappedRelativeWeight(period: uint256) -> uint256:
    """
    @dev Returns the gauge's relative weight, capped to its _relative_weight_cap attribute.
    """
    return min(GaugeController(GAUGE_CONTROLLER).gauge_relative_weight(self, period), self._relative_weight_cap)


@internal
def _setRelativeWeightCap(relative_weight_cap: uint256):
    assert relative_weight_cap <= MAX_RELATIVE_WEIGHT_CAP, "Relative weight cap exceeds allowed absolute maximum"
    self._relative_weight_cap = relative_weight_cap
    log RelativeWeightCapChanged(relative_weight_cap)


@external
def initialize(_bridger: address, _chain_id: uint256, _relative_weight_cap: uint256):
    """
    @notice Proxy initialization method
    @param _bridger The initial bridger address
    @param _chain_id The chainId of the corresponding ChildGauge
    @param _relative_weight_cap The initial relative weight cap
    """
    assert self.factory == empty(address)  # dev: already initialized

    self.chain_id = _chain_id
    self.bridger = _bridger
    self.factory = msg.sender

    inflation_params: InflationParams = InflationParams({
        rate: TokenAdmin(TOKEN_ADMIN).rate(),
        finish_time: TokenAdmin(TOKEN_ADMIN).future_epoch_time_write()
    })
    assert inflation_params.rate != 0

    self.inflation_params = inflation_params
    self.last_period = block.timestamp / WEEK
    self._setRelativeWeightCap(_relative_weight_cap)

    ERC20(TOKEN).approve(_bridger, max_value(uint256))
