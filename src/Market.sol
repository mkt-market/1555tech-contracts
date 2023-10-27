// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IBondingCurve} from "../interface/IBondingCurve.sol";
import {Turnstile} from "../interface/Turnstile.sol";

contract Market is ERC1155, Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant NFT_FEE_BPS = 1_000; // 10%
    uint256 public constant HOLDER_CUT_BPS = 33_000; // 33%
    uint256 public constant CREATOR_CUT_BPS = 33_000; // 33%
    // Platform cut: 100% - HOLDER_CUT_BPS - CREATOR_CUT_BPS

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Number of shares created
    uint256 public shareCount;

    /// @notice Stores the share ID of a given share name
    mapping(string => uint256) public shareIDs;

    /// @notice Stores the bonding curve per share
    mapping(uint256 => address) public shareBondingCurves;

    /// @notice Bonding curves that can be used for shares
    mapping(address => bool) whitelistedBondingCurves;

    /// @notice Stores the number of outstanding tokens per share
    mapping(uint256 => uint256) public tokenCount;

    /// @notice Accrued funds for the share holder
    mapping(uint256 => uint256) public shareHolderPool;

    /// @notice Accrued funds for the share creators
    mapping(uint256 => uint256) public shareCreatorPool;

    /// @notice Unclaimed funds for the platform
    uint256 platformPool;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event BondingCurveStateChange(address indexed curve, bool isWhitelisted);
    event ShareCreated(uint256 indexed id, string name, address indexed bondingCurve);

    /// @notice Initiates CSR on main- and testnet
    constructor(string memory _uri) ERC1155(_uri) Ownable(msg.sender) {
        if (block.chainid == 7700 || block.chainid == 7701) {
            // Register CSR on Canto main- and testnet
            Turnstile turnstile = Turnstile(0xEcf044C5B4b867CFda001101c617eCd347095B44);
            turnstile.register(tx.origin);
        }
    }

    /// @notice Whitelist or remove whitelist for a bonding curve.
    /// @dev Whitelisting status is only checked when adding a share
    /// @param _bondingCurve Address of the bonding curve
    /// @param _newState True if whitelisted, false if not
    function changeBondingCurveAllowed(address _bondingCurve, bool _newState) external onlyOwner {
        require(whitelistedBondingCurves[_bondingCurve] != _newState, "State already set");
        whitelistedBondingCurves[_bondingCurve] = _newState;
        emit BondingCurveStateChange(_bondingCurve, _newState);
    }

    /// @notice Creates a new share
    /// @param _shareName Name of the share
    /// @param _bondingCurve Address of the bonding curve, has to be whitelisted
    function createNewShare(string memory _shareName, address _bondingCurve) external returns (uint256 id) {
        require(whitelistedBondingCurves[_bondingCurve], "Bonding curve not whitelisted");
        require(shareIDs[_shareName] == 0, "Share already exists");
        id = ++shareCount;
        shareIDs[_shareName] = id;
        shareBondingCurves[id] = _bondingCurve;
        emit ShareCreated(id, _shareName, _bondingCurve);
    }

    /// @notice Buy amount of tokens for a given share ID
    /// @param _id ID of the share
    /// @param _amount Amount of shares to buy
    function buy(uint256 _id, uint256 _amount) external payable {
        address bondingCurve = shareBondingCurves[_id];
        require(bondingCurve != address(0), "Share does not exist");
        (uint256 price, uint256 fee) = IBondingCurve(bondingCurve).getBuyPriceAndFee(tokenCount[_id], _amount);
        require(msg.value >= price + fee, "Not enough funds sent");
        // Split the fee among holder, creator and platform
        uint256 shareHolderFee = fee * HOLDER_CUT_BPS / 100_000;
        uint256 shareCreatorFee = fee * CREATOR_CUT_BPS / 100_000;
        uint256 platformFee = fee - shareHolderFee - shareCreatorFee;
        shareHolderPool[_id] += shareHolderFee;
        shareCreatorPool[_id] += shareCreatorFee;
        platformPool += platformFee;

        tokenCount[_id] += _amount;

        // Refund the user if they sent too much
        uint256 difference = msg.value - price - fee;
        if (difference > 0) {
            _sendFunds(msg.sender, difference);
        }
    }

    /// @notice Sell amount of tokens for a given share ID
    /// @param _id ID of the share
    /// @param _amount Amount of shares to sell
    function sell(uint256 _id, uint256 _amount) external {
        address bondingCurve = shareBondingCurves[_id];
        require(bondingCurve != address(0), "Share does not exist");
        (uint256 price, uint256 fee) = IBondingCurve(bondingCurve).getSellPriceAndFee(tokenCount[_id], _amount);
        // Split the fee among holder, creator and platform
        uint256 shareHolderFee = fee * HOLDER_CUT_BPS / 100_000;
        uint256 shareCreatorFee = fee * CREATOR_CUT_BPS / 100_000;
        uint256 platformFee = fee - shareHolderFee - shareCreatorFee;
        shareHolderPool[_id] += shareHolderFee;
        shareCreatorPool[_id] += shareCreatorFee;
        platformPool += platformFee;

        tokenCount[_id] -= _amount;

        // Send the funds to the user
        _sendFunds(msg.sender, price);
    }

    function _sendFunds(address _to, uint256 _amount) internal {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Transfer failed");
    }
}
