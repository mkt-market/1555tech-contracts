// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.19;

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

    struct ShareData {
        uint256 tokenCount; // Number of outstanding tokens
        uint256 shareHolderRewardsPerTokenScaled; // Accrued funds for the share holder per token, multiplied by 1e18 to avoid precision loss
        uint256 shareCreatorPool; // Unclaimed funds for the share creators
        address bondingCurve; // Bonding curve used for this share
        address creator; // Creator of the share
    }

    /// @notice Stores the data for a given share ID
    mapping(uint256 => ShareData) public shareData;

    /// @notice Stores the bonding curve per share
    mapping(uint256 => address) public shareBondingCurves;

    /// @notice Bonding curves that can be used for shares
    mapping(address => bool) whitelistedBondingCurves;

    /// @notice Stores the number of outstanding tokens per share and address
    mapping(uint256 => mapping(address => uint256)) public tokensByAddress;

    /// @notice Value of ShareData.shareHolderRewardsPerTokenScaled at the last time a user claimed their rewards
    mapping(uint256 => mapping(address => uint256)) public rewardsLastClaimedValue;

    /// @notice Unclaimed funds for the platform
    uint256 platformPool;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event BondingCurveStateChange(address indexed curve, bool isWhitelisted);
    event ShareCreated(uint256 indexed id, string name, address indexed bondingCurve);
    event SharesBought(uint256 indexed id, address indexed buyer, uint256 amount, uint256 price, uint256 fee);
    event SharesSold(uint256 indexed id, address indexed seller, uint256 amount, uint256 price, uint256 fee);
    event NFTsCreated(uint256 indexed id, address indexed creator, uint256 amount, uint256 price, uint256 fee);
    event NFTsBurned(uint256 indexed id, address indexed burner, uint256 amount, uint256 price, uint256 fee);
    event PlatformFeeClaimed(address indexed claimer, uint256 amount);
    event CreatorFeeClaimed(address indexed claimer, uint256 indexed id, uint256 amount);
    event HolderFeeClaimed(address indexed claimer, uint256 indexed id, uint256 amount);

    /// @notice Initiates CSR on main- and testnet
    constructor(string memory _uri) ERC1155(_uri) Ownable() {
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
        shareData[id].bondingCurve = _bondingCurve;
        shareData[id].creator = msg.sender;
        emit ShareCreated(id, _shareName, _bondingCurve);
    }

    /// @notice Buy amount of tokens for a given share ID
    /// @param _id ID of the share
    /// @param _amount Amount of shares to buy
    function buy(uint256 _id, uint256 _amount) external payable {
        // If id does not exist, this will return address(0), causing a revert in the next line
        address bondingCurve = shareData[_id].bondingCurve;
        uint256 tokenCount = shareData[_id].tokenCount;
        (uint256 price, uint256 fee) = IBondingCurve(bondingCurve).getPriceAndFee(tokenCount, _amount);
        require(msg.value >= price + fee, "Not enough funds sent");
        // The reward calculation has to use the old rewards value (pre fee-split) to not include the fees of this buy
        // The rewardsLastClaimedValue then needs to be updated with the new value such that the user cannot claim fees of this buy
        uint256 rewardsSinceLastClaim = _getRewardsSinceLastClaim(_id);
        // Split the fee among holder, creator and platform
        _splitFees(_id, fee, tokenCount);
        rewardsLastClaimedValue[_id][msg.sender] = shareData[_id].shareHolderRewardsPerTokenScaled;

        shareData[_id].tokenCount += _amount;
        tokensByAddress[_id][msg.sender] += _amount;

        // Refund the user if they sent too much
        uint256 difference = msg.value - price - fee;
        rewardsSinceLastClaim += difference;
        if (rewardsSinceLastClaim > 0) {
            _sendFunds(msg.sender, rewardsSinceLastClaim);
        }
        emit SharesBought(_id, msg.sender, _amount, price, fee);
    }

    /// @notice Sell amount of tokens for a given share ID
    /// @param _id ID of the share
    /// @param _amount Amount of shares to sell
    function sell(uint256 _id, uint256 _amount) external {
        // If id does not exist, this will return address(0), causing a revert in the next line
        address bondingCurve = shareData[_id].bondingCurve;
        uint256 tokenCount = shareData[_id].tokenCount;
        (uint256 price, uint256 fee) = IBondingCurve(bondingCurve).getPriceAndFee(tokenCount, _amount);
        // Split the fee among holder, creator and platform
        _splitFees(_id, fee, tokenCount);
        // The user also gets the rewards of his own sale (which is not the case for buys)
        uint256 rewardsSinceLastClaim = _getRewardsSinceLastClaim(_id);
        rewardsLastClaimedValue[_id][msg.sender] = shareData[_id].shareHolderRewardsPerTokenScaled;

        shareData[_id].tokenCount -= _amount;
        tokensByAddress[_id][msg.sender] -= _amount; // Would underflow if user did not have enough tokens

        // Send the funds to the user
        _sendFunds(msg.sender, rewardsSinceLastClaim + price - fee);
        emit SharesSold(_id, msg.sender, _amount, price, fee);
    }

    function mintNFT(uint256 _id, uint256 _amount) external payable {
        address bondingCurve = shareData[_id].bondingCurve;
        uint256 tokenCount = shareData[_id].tokenCount;
        (uint256 priceForOne, uint256 feeForOne) = IBondingCurve(bondingCurve).getPriceAndFee(tokenCount, 1);
        uint256 price = (priceForOne * _amount * NFT_FEE_BPS) / 100_000;
        uint256 fee = feeForOne * _amount;
        require(msg.value >= price + fee, "Not enough funds sent");
        _splitFees(_id, fee, tokenCount);
        // The user also gets the proportional rewards for the minting
        uint256 rewardsSinceLastClaim = _getRewardsSinceLastClaim(_id);
        rewardsLastClaimedValue[_id][msg.sender] = shareData[_id].shareHolderRewardsPerTokenScaled;
        tokensByAddress[_id][msg.sender] -= _amount;

        _mint(msg.sender, _id, _amount, "");

        // Refund the user if they sent too much
        uint256 difference = msg.value - price - fee;
        rewardsSinceLastClaim += difference;
        if (rewardsSinceLastClaim > 0) {
            _sendFunds(msg.sender, rewardsSinceLastClaim);
        }
        // ERC1155 already logs, but we add this to have the price information
        emit NFTsCreated(_id, msg.sender, _amount, price, fee);
    }

    function burnNFT(uint256 _id, uint256 _amount) external {
        address bondingCurve = shareData[_id].bondingCurve;
        uint256 tokenCount = shareData[_id].tokenCount;
        (uint256 priceForOne, uint256 feeForOne) = IBondingCurve(bondingCurve).getPriceAndFee(tokenCount, 1);
        uint256 price = (priceForOne * _amount * NFT_FEE_BPS) / 100_000;
        uint256 fee = feeForOne * _amount;
        _splitFees(_id, fee, tokenCount);
        // The user does not get the proportional rewards for the burning (unless they have additional tokens that are not in the NFT)
        uint256 rewardsSinceLastClaim = _getRewardsSinceLastClaim(_id);
        rewardsLastClaimedValue[_id][msg.sender] = shareData[_id].shareHolderRewardsPerTokenScaled;
        tokensByAddress[_id][msg.sender] += _amount;
        _burn(msg.sender, _id, _amount);

        _sendFunds(msg.sender, rewardsSinceLastClaim + price - fee);
        // ERC1155 already logs, but we add this to have the price information
        emit NFTsBurned(_id, msg.sender, _amount, price, fee);
    }

    /// @notice Withdraws the accrued platform fee
    function claimPlatformFee() external onlyOwner {
        uint256 amount = platformPool;
        platformPool = 0;
        _sendFunds(msg.sender, amount);
        emit PlatformFeeClaimed(msg.sender, amount);
    }

    /// @notice Withdraws the accrued share creator fee
    /// @param _id ID of the share
    function claimCreatorFee(uint256 _id) external {
        require(shareData[_id].creator == msg.sender, "Not creator");
        uint256 amount = shareData[_id].shareCreatorPool;
        shareData[_id].shareCreatorPool = 0;
        _sendFunds(msg.sender, amount);
        emit CreatorFeeClaimed(msg.sender, _id, amount);
    }

    function claimHolderFee(uint256 _id) external {
        uint256 amount = _getRewardsSinceLastClaim(_id);
        rewardsLastClaimedValue[_id][msg.sender] = shareData[_id].shareHolderRewardsPerTokenScaled;
        if (amount > 0) {
            _sendFunds(msg.sender, amount);
        }
        emit HolderFeeClaimed(msg.sender, _id, amount);
    }

    function _getRewardsSinceLastClaim(uint256 _id) internal view returns (uint256 amount) {
        uint256 lastClaimedValue = rewardsLastClaimedValue[_id][msg.sender];
        amount =
            ((shareData[_id].shareHolderRewardsPerTokenScaled - lastClaimedValue) * tokensByAddress[_id][msg.sender]) /
            1e18;
    }

    /// @notice Splits the fee among the share holder, creator and platform
    function _splitFees(
        uint256 _id,
        uint256 _fee,
        uint256 _tokenCount
    ) internal {
        uint256 shareHolderFee = (_fee * HOLDER_CUT_BPS) / 100_000;
        uint256 shareCreatorFee = (_fee * CREATOR_CUT_BPS) / 100_000;
        uint256 platformFee = _fee - shareHolderFee - shareCreatorFee;
        shareData[_id].shareCreatorPool += shareCreatorFee;
        if (_tokenCount > 0) {
            shareData[_id].shareHolderRewardsPerTokenScaled += (shareHolderFee * 1e18) / _tokenCount;
        } else {
            // On the first buy, no share holders exist yet, so the fee goes to the platform
            platformFee += shareHolderFee;
        }
        platformPool += platformFee;
    }

    function _sendFunds(address _to, uint256 _amount) internal {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Transfer failed");
    }
}
