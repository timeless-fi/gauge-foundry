# @version 0.3.7
"""
@notice Curve Gnosis (prev Xdai) Omni Bridge Wrapper
@dev See https://docs.openzeppelin.com/contracts/4.x/api/crosschain#CrossChainEnabledAMB for the list
of bridges supported by Omni
"""
from vyper.interfaces import ERC20


interface OmniBridge:
    def relayTokens(_token: address, _receiver: address, _value: uint256): nonpayable


OMNI_BRIDGE: immutable(address)
TOKEN: immutable(address)

is_approved: public(HashMap[address, bool])


@external
def __init__(_token: address, _omni_bridge: address):
    TOKEN = _token
    OMNI_BRIDGE = _omni_bridge

    assert ERC20(_token).approve(_omni_bridge, max_value(uint256), default_return_value=True)
    self.is_approved[_token] = True


@external
def bridge(_token: address, _to: address, _amount: uint256):
    """
    @notice Bridge an asset using the Omni Bridge
    @param _token The ERC20 asset to bridge
    @param _to The receiver on Gnosis Chain
    @param _amount The amount of `_token` to bridge
    """
    assert ERC20(_token).transferFrom(msg.sender, self, _amount, default_return_value=True)

    if _token != TOKEN and not self.is_approved[_token]:
        assert ERC20(_token).approve(OMNI_BRIDGE, max_value(uint256), default_return_value=True)
        self.is_approved[_token] = True

    OmniBridge(OMNI_BRIDGE).relayTokens(_token, _to, _amount)


@pure
@external
def cost() -> uint256:
    """
    @notice Cost in ETH to bridge
    """
    return 0


@pure
@external
def check(_account: address) -> bool:
    """
    @notice Check if `_account` may bridge via `transmit_emissions`
    @param _account The account to check
    """
    return True