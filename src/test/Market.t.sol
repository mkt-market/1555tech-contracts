pragma solidity ^0.8.0;

import "forge-std/test.sol";
import "../Market.sol";
import "../bonding_curve/LinearBondingCurve.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

contract MarketTest is Test {
    Market market;
    LinearBondingCurve bondingCurve;
    MockERC20 token;
    uint256 constant LINEAR_INCREASE = 1e18 / 1000;
    address bob;
    address alice;

    function setUp() public {
        bondingCurve = new LinearBondingCurve(LINEAR_INCREASE);
        token = new MockERC20("Mock Token", "MTK", 1e18);
        market = new Market("http://uri.xyz", address(token));
        bob = address(1);
        alice = address(2);
    }

    function testChangeBondingCurveAllowed() public {
        market.changeBondingCurveAllowed(address(bondingCurve), true);
        assertTrue(market.whitelistedBondingCurves(address(bondingCurve)));

        market.changeBondingCurveAllowed(address(bondingCurve), false);
        assertFalse(market.whitelistedBondingCurves(address(bondingCurve)));
    }

    function testFailCreateNewShareWhenBondingCurveNotWhitelisted() public {
        vm.expectRevert("Bonding curve not whitelisted");
        market.createNewShare("Test Share", address(bondingCurve), "metadataURI");
    }

    function testCreateNewShare() public {
        market.changeBondingCurveAllowed(address(bondingCurve), true);
        market.createNewShare("Test Share", address(bondingCurve), "metadataURI");
        assertEq(market.shareIDs("Test Share"), 1);
    }
}