pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../Market.sol";
import "../bonding_curve/WeightedPoolBondingCurve.sol";
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
    WeightedPoolBondingCurve bondingCurve;
    MockERC20 token;
    uint256 constant weight = 5000;
    address bob;
    address alice;

    function setUp() public {
        bondingCurve = new WeightedPoolBondingCurve(weight);
        token = new MockERC20("Mock Token", "MTK", 1000e18);
        market = new Market(address(token), address(this));
        bob = address(1);
        alice = address(2);
    }

    function testChangeBondingCurveAllowed() public {
        market.changeBondingCurveAllowed(address(bondingCurve), true);
        assertTrue(market.whitelistedBondingCurves(address(bondingCurve)));

        market.changeBondingCurveAllowed(address(bondingCurve), false);
        assertFalse(market.whitelistedBondingCurves(address(bondingCurve)));
    }

    function testChangeBondingCurveAllowedNonOwnerFails() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(bob);
        market.changeBondingCurveAllowed(address(bondingCurve), true);
    }

    function testCreateNewShareWhenBondingCurveNotWhitelistedFails() public {
        vm.expectRevert("Bonding curve not whitelisted");
        uint256 presaleDummy = 42;
        Market.PresaleData memory presaleData = Market.PresaleData(
            5e18,
            block.timestamp + 90 days,
            block.timestamp + 730 days,
            bytes32(abi.encodePacked(presaleDummy))
        );
        Market.DutchAuctionData memory dutchAuctionData = Market.DutchAuctionData(
            0,
            10e18,
            0.1e18,
            block.timestamp + 90 days,
            block.timestamp + 730 days
        );
        market.createNewShare(
            "Test Share",
            address(bondingCurve),
            "metadataURI",
            400,
            400,
            200,
            presaleData,
            dutchAuctionData
        );
    }

    function testCreateNewShare() public {
        market.changeBondingCurveAllowed(address(bondingCurve), true);
        market.restrictShareCreation(false);
        vm.prank(bob);
        uint256 presaleDummy = 42;
        Market.PresaleData memory presaleData = Market.PresaleData(
            5e18,
            block.timestamp + 90 days,
            block.timestamp + 730 days,
            bytes32(abi.encodePacked(presaleDummy))
        );
        Market.DutchAuctionData memory dutchAuctionData = Market.DutchAuctionData(
            0,
            10e18,
            0.1e18,
            block.timestamp + 90 days,
            block.timestamp + 730 days
        );
        market.createNewShare(
            "Test Share",
            address(bondingCurve),
            "metadataURI",
            400,
            400,
            200,
            presaleData,
            dutchAuctionData
        );
        assertEq(market.shareIDs("Test Share"), 1);
    }

    function testDutchBuy() public {
        testCreateNewShare();
        token.approve(address(market), 10e18);
        vm.prank(bob);
        market.endPresale(1);
        market.buyDutch(1, 1, 10e18);
        assertEq(token.balanceOf(address(market)), 10e18);
    }

    function testBondingCurveBuyDuringPresale() public {
        testCreateNewShare();
        vm.expectRevert("No bonding curve");
        market.buy(1, 1, 1e18);
    }

    function testDutchBuyDuringPresale() public {
        testCreateNewShare();
        vm.expectRevert("No dutch auction");
        market.buyDutch(1, 1, 1e18);
    }

    function testBondingCurveBuy() public {
        testCreateNewShare();
        token.approve(address(market), 10e18);
        vm.startPrank(bob);
        market.endPresale(1);
        market.endDutchAuction(1);
        vm.stopPrank();
        market.buy(1, 1, 3e18);
        assertEq(token.balanceOf(address(market)), 5024875621890548 + 502487562189054);
    }

    function testGetBuyPrice() public {
        testCreateNewShare();
        token.approve(address(market), 10e18);
        vm.startPrank(bob);
        market.endPresale(1);
        market.endDutchAuction(1);
        vm.stopPrank();
        (uint256 price, uint256 fee) = market.getBuyPrice(1, 1);
        assertEq(price, 5024875621890548);
        assertEq(fee, 502487562189054);
    }

    function testGetSellPrice() public {
        testBondingCurveBuy();
        (uint256 price, uint256 fee) = market.getSellPrice(1, 1);
        assertEq(price, 5024875621890548);
        assertEq(fee, 502487562189054);
    }

    function testEndPresaleNonOwner() public {
        testCreateNewShare();
        vm.prank(alice);
        vm.expectRevert("Not allowed");
        market.endPresale(1);
    }

    function testEndDutchNonOwner() public {
        testCreateNewShare();
        vm.prank(bob);
        market.endPresale(1);
        vm.prank(alice);
        vm.expectRevert("Not allowed");
        market.endDutchAuction(1);
    }

    // function testGetBuyPrice() public {
    //     testCreateNewShare();
    //     (uint256 priceOne, uint256 feeOne) = market.getBuyPrice(1, 1);
    //     (uint256 priceTwo, uint256 feeTwo) = market.getBuyPrice(1, 2);
    //     assertEq(priceOne, LINEAR_INCREASE);
    //     assertEq(priceTwo, priceOne + LINEAR_INCREASE * 2);
    //     assertEq(feeOne, priceOne / 10);
    //     assertEq(feeTwo, priceTwo / 10); // log2(2) = 1
    // }

    // function testBuy() public {
    //     testCreateNewShare();
    //     token.approve(address(market), 1e18);
    //     market.buy(1, 1, type(uint256).max);
    //     assertEq(token.balanceOf(address(market)), LINEAR_INCREASE + LINEAR_INCREASE / 10);
    //     assertEq(token.balanceOf(address(this)), 1e18 - LINEAR_INCREASE - LINEAR_INCREASE / 10);
    // }

    // function testSell() public {
    //     testBuy();
    //     market.sell(1, 1, 0);
    //     uint256 fee = LINEAR_INCREASE / 10;
    //     // Because of autoclaiming, 2/3 is transferred back
    //     assertEq(token.balanceOf(address(market)), fee + (fee * 34) / 100);
    //     assertEq(token.balanceOf(address(this)), 1e18 - (fee + (fee * 34) / 100));
    // }

    // function testMint() public {
    //     testBuy();
    //     market.mintNFT(1, 1);
    //     uint256 fee = LINEAR_INCREASE / 10;
    //     // Get back two thirds because of autoclaiming
    //     assertEq(token.balanceOf(address(market)), LINEAR_INCREASE + 2 * fee - (fee * 66) / 100);
    // }

    // function testBurn() public {
    //     testMint();
    //     market.burnNFT(1, 1);
    //     uint256 fee = LINEAR_INCREASE / 10;
    //     assertEq(token.balanceOf(address(market)), LINEAR_INCREASE + 3 * fee - (fee * 66) / 100);
    // }

    function claimCreatorFeeNonCreator() public {
        testCreateNewShare();
        vm.expectRevert("Not creator");
        vm.prank(alice);
        market.claimCreatorFee(1);
    }

    // function claimCreator() public {
    //     testBuy();
    //     vm.prank(bob);
    //     market.claimCreatorFee(1);
    //     uint256 fee = LINEAR_INCREASE / 10;
    //     assertEq(token.balanceOf(bob), (fee * 33) / 100);
    // }

    // function claimPlatform() public {
    //     testBuy();
    //     uint256 balBefore = token.balanceOf(address(this));
    //     market.claimPlatformFee();
    //     uint256 fee = LINEAR_INCREASE / 10;
    //     assertEq(token.balanceOf(address(this)), balBefore + (fee * 67) / 100);
    // }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
