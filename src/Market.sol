// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IBondingCurve} from "../interface/IBondingCurve.sol";
import {Turnstile} from "../interface/Turnstile.sol";
import {MerkleProof} from "openzeppelin/utils/cryptography/MerkleProof.sol";

contract Market is ERC1155, Ownable2Step, EIP712 {
    /*//////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant NFT_FEE_BPS = 1_000; // 10%
    uint256 public constant HOLDER_CUT_BPS = 3_300; // 33%
    uint256 public constant CREATOR_CUT_BPS = 3_300; // 33%
    // Platform cut: 100% - HOLDER_CUT_BPS - CREATOR_CUT_BPS

    /// @notice Payment token
    IERC20 public immutable token;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Number of shares created
    uint256 public shareCount;

    /// @notice Stores the share ID of a given share name
    mapping(string => uint256) public shareIDs;

    struct ShareData {
        uint256 tokenCount; // Number of outstanding tokens
        uint256 tokensInCirculation; // Number of outstanding tokens - tokens that are minted as NFT, i.e. the number of tokens that receive fees
        uint256 shareHolderRewardsPerTokenScaled; // Accrued funds for the share holder per token, multiplied by 1e18 to avoid precision loss
        uint256 shareCreatorPool; // Unclaimed funds for the share creators
        address bondingCurve; // Bonding curve used for this share
        address creator; // Creator of the share
        address owner; // Address that can claim rewards
        string metadataURI; // URI of the metadata
        uint256 tokenCountBondingCurve; // Number of tokens in the bonding curve
        uint256 numTokens; // Maximum number of tokens that can be minted
        uint16 presaleBps; // Percentage (in BPS) of the presale allocation
        bool presale; // If true, no bonding curve buys are possible, only pre sale allocation and dutch auction
        bytes32 presaleTreeRoot; // Merkle root of the presale allocation
        uint256 presalePrice; // Price of the presale
        uint40 presaleVestingStart; // Start of the presale vesting period
        uint40 presaleVestingEnd; // End of the presale vesting period
        uint16 dutchAuctionBps; // Percentage (in BPS) of the dutch auction allocation
        uint40 dutchAuctionStart; // Start of the dutch auction
        uint256 dutchAuctionStartPrice; // Start price of the dutch auction
        uint256 dutchAuctionDiscountRate; // Discount rate of the dutch auction (per second)
        uint256 dutchAuctionVestingStart; // Start of the dutch auction vesting period
        uint256 dutchAuctionVestingEnd; // End of the dutch auction vesting period
    }

    /// @notice Stores the data for a given share ID
    mapping(uint256 => ShareData) public shareData;

    struct VestData {
        uint256 bought;
        uint256 vested;
    }

    /// @notice Stores the vest metadata for the presale
    mapping(uint256 => mapping(address => VestData)) public presaleVestData;

    /// @notice Stores the vest metadata for the dutch auction
    mapping(uint256 => mapping(address => VestData)) public dutchAuctionVestData;

    /// @notice Bonding curves that can be used for shares
    mapping(address => bool) public whitelistedBondingCurves;

    /// @notice Stores the number of outstanding tokens per share and address
    mapping(uint256 => mapping(address => uint256)) public tokensByAddress;

    /// @notice Value of ShareData.shareHolderRewardsPerTokenScaled at the last time a user claimed their rewards
    mapping(uint256 => mapping(address => uint256)) public rewardsLastClaimedValue;

    /// @notice Unclaimed funds for the platform
    uint256 public platformPool;

    /// @notice If true, only the whitelisted addresses can create shares
    bool public shareCreationRestricted = true;

    /// @notice List of addresses that can add new shares when shareCreationRestricted is true
    mapping(address => bool) public whitelistedShareCreators;

    /// @notice Address that signs data for creator whitelisting
    address offchainSigner;

    /// @notice Name of the token.
    /// @dev According to ERC1155, this is not required/part of the standard, but Blockscout parses it
    string public constant name = "1155tech";

    /// @notice Symbol of the token.
    /// @dev According to ERC1155, this is not required/part of the standard, but Blockscout parses it
    string public constant symbol = "1155tech";

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event BondingCurveStateChange(address indexed curve, bool isWhitelisted);
    event ShareCreated(uint256 indexed id, string name, address indexed bondingCurve, address indexed creator);
    event SharesBought(uint256 indexed id, address indexed buyer, uint256 amount, uint256 price, uint256 fee);
    event SharesSold(uint256 indexed id, address indexed seller, uint256 amount, uint256 price, uint256 fee);
    event NFTsCreated(uint256 indexed id, address indexed creator, uint256 amount, uint256 fee);
    event NFTsBurned(uint256 indexed id, address indexed burner, uint256 amount, uint256 fee);
    event PlatformFeeClaimed(address indexed claimer, uint256 amount);
    event CreatorFeeClaimed(address indexed claimer, uint256 indexed id, uint256 amount);
    event HolderFeeClaimed(
        address indexed claimer,
        uint256 indexed id,
        uint256 amount,
        uint256 currRewardsLastClaimedValue
    );
    event ShareCreationRestricted(bool isRestricted);
    event ShareOwnerUpdated(uint256 indexed id, address indexed newOwner);
    event ShareSaleStarted(uint256 indexed id);

    modifier onlyShareCreator() {
        require(
            !shareCreationRestricted || whitelistedShareCreators[msg.sender] || msg.sender == owner(),
            "Not allowed"
        );
        _;
    }

    /// @notice Initiates CSR on main- and testnet
    /// @param _paymentToken Address of the payment token
    /// @param _offchainSigner Address that signs data for creator whitelisting
    constructor(address _paymentToken, address _offchainSigner) ERC1155("") Ownable() EIP712("1155tech", "1") {
        token = IERC20(_paymentToken);
        offchainSigner = _offchainSigner;
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
    /// @param _metadataURI URI of the metadata
    /// @param _numTokens Maximum number of tokens that can be minted
    /// @param _presaleBps Percentage (in BPS) of the presale allocation
    /// @param _presaleTreeRoot Merkle root of the presale allocation
    /// @param _presalePrice Price of the presale
    /// @param _presaleVestingStart Start of the presale vesting period
    /// @param _presaleVestingEnd End of the presale vesting period
    /// @param _dutchAuctionBps Percentage (in BPS) of the dutch auction allocation
    /// @param _dutchAuctionStart Start timestamp of the dutch auction
    /// @param _dutchAuctionStartPrice Start price of the dutch auction
    /// @param _dutchAuctionDiscountRate Discount rate of the dutch auction (per second)
    function createNewShare(
        string memory _shareName,
        address _bondingCurve,
        string memory _metadataURI,
        uint256 _numTokens,
        uint16 _presaleBps,
        bytes32 _presaleTreeRoot,
        uint256 _presalePrice,
        uint40 _presaleVestingStart,
        uint40 _presaleVestingEnd,
        uint16 _dutchAuctionBps,
        uint40 _dutchAuctionStart,
        uint256 _dutchAuctionStartPrice,
        uint256 _dutchAuctionDiscountRate,
        uint256 _dutchAuctionVestingStart,
        uint256 _dutchAuctionVestingEnd
    ) external onlyShareCreator returns (uint256 id) {
        require(whitelistedBondingCurves[_bondingCurve], "Bonding curve not whitelisted");
        require(shareIDs[_shareName] == 0, "Share already exists");
        require(bytes(_metadataURI).length > 0, "No metadata URI provided");
        id = ++shareCount;
        shareIDs[_shareName] = id;
        shareData[id].bondingCurve = _bondingCurve;
        shareData[id].creator = msg.sender;
        shareData[id].owner = msg.sender;
        shareData[id].metadataURI = _metadataURI;
        shareData[id].numTokens = _numTokens;
        shareData[id].presaleBps = _presaleBps;
        shareData[id].presaleTreeRoot = _presaleTreeRoot;
        shareData[id].presalePrice = _presalePrice;
        shareData[id].presaleVestingStart = _presaleVestingStart;
        shareData[id].presaleVestingEnd = _presaleVestingEnd;
        shareData[id].dutchAuctionBps = _dutchAuctionBps;
        shareData[id].presale = _presaleBps > 0;
        shareData[id].dutchAuctionStart = _dutchAuctionStart;
        shareData[id].dutchAuctionStartPrice = _dutchAuctionStartPrice;
        shareData[id].dutchAuctionDiscountRate = _dutchAuctionDiscountRate;
        shareData[id].dutchAuctionVestingStart = _dutchAuctionVestingStart;
        shareData[id].dutchAuctionVestingEnd = _dutchAuctionVestingEnd;
        emit ShareCreated(id, _shareName, _bondingCurve, msg.sender);
        emit URI(_metadataURI, id); // Emit ERC1155 URI event
    }

    /// @notice Returns the ERC1155 metadata URI for a given share ID
    /// @param _id The ID of the ERC1155 token
    function uri(uint256 _id) public view override returns (string memory) {
        require(_id > 0 && _id <= shareCount, "Invalid ID");
        return shareData[_id].metadataURI;
    }

    /// @notice Returns the price and fee for buying a given number of shares.
    /// @param _id The ID of the share
    /// @param _amount The number of shares to buy.
    function getBuyPrice(uint256 _id, uint256 _amount) public view returns (uint256 price, uint256 fee) {
        // If id does not exist, this will return address(0), causing a revert in the next line
        ShareData storage share = shareData[_id];
        address bondingCurve = share.bondingCurve;
        (price, fee) = IBondingCurve(bondingCurve).getPriceAndFee(
            share.tokenCount + 1,
            share.tokenCountBondingCurve + 1,
            _amount
        );
    }

    /// @notice Returns the price and fee for selling a given number of shares.
    /// @param _id The ID of the share
    /// @param _amount The number of shares to sell.
    function getSellPrice(uint256 _id, uint256 _amount) public view returns (uint256 price, uint256 fee) {
        // If id does not exist, this will return address(0), causing a revert in the next line
        ShareData storage share = shareData[_id];
        address bondingCurve = share.bondingCurve;
        (price, fee) = IBondingCurve(bondingCurve).getPriceAndFee(
            share.tokenCount - _amount + 1,
            share.tokenCountBondingCurve - _amount + 1,
            _amount
        );
    }

    /// @notice Ends the presale and starts the normal sale for a given share ID
    /// @param _id ID of the share
    function endPresale(uint256 _id) external {
        require(shareData[_id].owner == msg.sender, "Not owner");
        require(shareData[_id].presale, "No presale");
        shareData[_id].presale = false;
        emit ShareSaleStarted(_id);
    }

    /// @notice Buy amount of tokens for a given share ID in the presale
    /// @param _id ID of the share
    /// @param _amountToBuy Amount of shares to buy
    /// @param _amountAllocation Amount of tokens allocated to the user
    /// @param _merkleProof Merkle proof for the allocation
    function buyPresale(
        uint256 _id,
        uint256 _amountToBuy,
        uint256 _amountAllocation,
        bytes32[] calldata _merkleProof
    ) external {
        require(shareData[_id].presale, "No presale");
        require(
            MerkleProof.verify(
                _merkleProof,
                shareData[_id].presaleTreeRoot,
                keccak256(abi.encode(msg.sender, _amountAllocation))
            ),
            "Invalid proof"
        );
        require(presaleVestData[_id][msg.sender].bought + _amountToBuy <= _amountAllocation, "More than allocation");

        presaleVestData[_id][msg.sender].bought += _amountToBuy; // Get added to tokencount when vesting starts
        uint256 price = shareData[_id].presalePrice * _amountToBuy;
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), price);
        emit SharesBought(_id, msg.sender, _amountToBuy, price, 0);
    }

    /// @notice Buy amount of tokens for a given share ID in the dutch auction
    /// @param _id ID of the share
    /// @param _amount Amount of shares to buy
    /// @param _maxPrice Maximum price that user is willing to buy (for the whole sale)
    function buyDutch(
        uint256 _id,
        uint256 _amount,
        uint256 _maxPrice
    ) external {
        require(shareData[_id].creator != msg.sender, "Creator cannot buy");
        uint256 timeElapsed = block.timestamp - shareData[_id].dutchAuctionStart; // Underflows if not started yet
        uint256 discount = timeElapsed * shareData[_id].dutchAuctionDiscountRate;
        uint256 price;
        if (discount < price) {
            price = (shareData[_id].dutchAuctionStartPrice - discount) * _amount;
        }

        // TODO: Check maximum amount

        require(price <= _maxPrice, "Price too high");
        dutchAuctionVestData[_id][msg.sender].bought += _amount;

        SafeERC20.safeTransferFrom(token, msg.sender, address(this), price);
        emit SharesBought(_id, msg.sender, _amount, price, 0);
    }

    /// @notice Vest the tokens for a given share ID
    /// @param _id ID of the share
    /// @param _vestingStart Start of the vesting period
    /// @param _vestingEnd End of the vesting period
    /// @param _vestData Vesting data for the user
    function _vestTokens(
        uint256 _id,
        uint256 vestingStart,
        uint256 vestingEnd,
        VestData storage vestData
    ) internal {
        uint256 amount = vestData.bought;
        uint256 vested = vestData.vested;
        if (block.timestamp < vestingStart || amount == vested) return;
        uint256 vestingDuration = vestingEnd - vestingStart;
        uint256 timeSinceStart = block.timestamp - vestingStart;
        uint256 vestedNow = (amount * timeSinceStart) / vestingDuration;
        if (vestedNow > amount) {
            vestedNow = amount;
        }
        uint256 toVest = vestedNow - vested;
        vestData.vested = vestedNow;
        shareData[_id].tokenCount += toVest;
        shareData[_id].tokensInCirculation += toVest;
        shareData[_id].tokenCountBondingCurve += toVest;
    }

    /// @notice Vest the presale tokens for a given share ID
    /// @param _id ID of the share
    function vestPresale(uint256 _id) public {
        _vestTokens(
            _id,
            shareData[_id].presaleVestingStart,
            shareData[_id].presaleVestingEnd,
            presaleVestData[_id][msg.sender]
        );
    }

    /// @notice Vest the dutch auction tokens for a given share ID
    /// @param _id ID of the share
    function vestDutchAuction(uint256 _id) public {
        _vestTokens(
            _id,
            shareData[_id].dutchAuctionVestingStart,
            shareData[_id].dutchAuctionVestingEnd,
            dutchAuctionVestData[_id][msg.sender]
        );
    }

    /// @notice Buy amount of tokens for a given share ID
    /// @param _id ID of the share
    /// @param _amount Amount of shares to buy
    /// @param _maxPrice Maximum price that user is willing to buy (for the whole sale)
    function buy(
        uint256 _id,
        uint256 _amount,
        uint256 _maxPrice
    ) public {
        require(!shareData[_id].presale, "Presale only");
        require(shareData[_id].creator != msg.sender, "Creator cannot buy");
        (uint256 price, uint256 fee) = getBuyPrice(_id, _amount); // Reverts for non-existing ID
        require(price <= _maxPrice, "Price too high");
        claimHolderFee(_id);

        shareData[_id].tokenCount += _amount;
        shareData[_id].tokenCountBondingCurve += _amount;
        shareData[_id].tokensInCirculation += _amount;
        tokensByAddress[_id][msg.sender] += _amount;

        // The user also gets the rewards of his own buy (i.e., a small cashback)
        _splitFees(_id, fee, shareData[_id].tokensInCirculation);

        SafeERC20.safeTransferFrom(token, msg.sender, address(this), price + fee);
        emit SharesBought(_id, msg.sender, _amount, price, fee);
    }

    /// @notice Perform multiple buys in one transaction
    /// @param _ids IDs of the shares
    /// @param _amounts Amounts of shares to buy
    /// @param _maxPrices Maximum prices that user is willing to buy (for the whole sale)
    function multiBuy(
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        uint256[] calldata _maxPrices
    ) external {
        require(_ids.length == _amounts.length && _ids.length == _maxPrices.length, "Length mismatch");
        for (uint256 i = 0; i < _ids.length; i++) {
            buy(_ids[i], _amounts[i], _maxPrices[i]);
        }
    }

    /// @notice Sell amount of tokens for a given share ID
    /// @param _id ID of the share
    /// @param _amount Amount of shares to sell
    /// @param _minPrice Minimum price that user wants to receive (for the whole sale)
    /// @param _autoVest If true, vest will be called automatically
    function sell(
        uint256 _id,
        uint256 _amount,
        uint256 _minPrice,
        bool _autoVest
    ) public {
        require(!shareData[_id].presale, "Presale only");
        (uint256 price, uint256 fee) = getSellPrice(_id, _amount);
        require(price >= _minPrice, "Price too low");
        if (_autoVest) {
            vestPresale(_id);
            vestDutchAuction(_id);
        }
        // Split the fee among holder, creator and platform
        _splitFees(_id, fee, shareData[_id].tokensInCirculation);
        // The user also gets the rewards of his own sale
        claimHolderFee(_id);

        shareData[_id].tokenCount -= _amount;
        shareData[_id].tokenCountBondingCurve -= _amount;
        shareData[_id].tokensInCirculation -= _amount;
        tokensByAddress[_id][msg.sender] -= _amount; // Would underflow if user did not have enough tokens

        // Send the funds to the user
        SafeERC20.safeTransfer(token, msg.sender, price - fee);
        emit SharesSold(_id, msg.sender, _amount, price, fee);
    }

    /// @notice Perform multiple sells in one transaction
    /// @param _ids IDs of the shares
    /// @param _amounts Amounts of shares to sell
    /// @param _minPrices Minimum prices that user wants to receive (for the whole sale)
    /// @param _autoVest If true, vest will be called automatically
    function multiSell(
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        uint256[] calldata _minPrices,
        bool _autoVest
    ) external {
        require(_ids.length == _amounts.length && _ids.length == _minPrices.length, "Length mismatch");
        for (uint256 i = 0; i < _ids.length; i++) {
            sell(_ids[i], _amounts[i], _minPrices[i], _autoVest);
        }
    }

    /// @notice Returns the price for minting a given number of NFTs.
    /// @param _id The ID of the share
    /// @param _amount The number of NFTs to mint.
    function getNFTMintingPrice(uint256 _id, uint256 _amount) public view returns (uint256 fee) {
        ShareData storage share = shareData[_id];
        address bondingCurve = share.bondingCurve;
        (uint256 priceForOne, ) = IBondingCurve(bondingCurve).getPriceAndFee(
            share.tokenCount,
            share.tokenCountBondingCurve,
            1
        );
        fee = (priceForOne * _amount * NFT_FEE_BPS) / 10_000;
    }

    /// @notice Convert amount of tokens to NFTs for a given share ID
    /// @param _id ID of the share
    /// @param _amount Amount of tokens to convert. User needs to have this many tokens.
    /// @param _autoVest If true, vest will be called automatically
    function mintNFT(
        uint256 _id,
        uint256 _amount,
        bool _autoVest
    ) external {
        if (_autoVest) {
            vestPresale(_id);
            vestDutchAuction(_id);
        }
        uint256 fee = getNFTMintingPrice(_id, _amount);

        _splitFees(_id, fee, shareData[_id].tokensInCirculation);
        // The user also gets the proportional rewards for the minting
        claimHolderFee(_id);
        tokensByAddress[_id][msg.sender] -= _amount;
        shareData[_id].tokensInCirculation -= _amount;

        SafeERC20.safeTransferFrom(token, msg.sender, address(this), fee);

        _mint(msg.sender, _id, _amount, "");

        // ERC1155 already logs, but we add this to have the price information
        emit NFTsCreated(_id, msg.sender, _amount, fee);
    }

    /// @notice Burn amount of NFTs for a given share ID to get back tokens
    /// @param _id ID of the share
    /// @param _amount Amount of NFTs to burn
    function burnNFT(uint256 _id, uint256 _amount) external {
        uint256 fee = getNFTMintingPrice(_id, _amount);

        _splitFees(_id, fee, shareData[_id].tokensInCirculation);
        // The user does not get the proportional rewards for the burning (unless they have additional tokens that are not in the NFT)
        claimHolderFee(_id);
        tokensByAddress[_id][msg.sender] += _amount;
        shareData[_id].tokensInCirculation += _amount;
        _burn(msg.sender, _id, _amount);

        SafeERC20.safeTransferFrom(token, msg.sender, address(this), fee);
        // ERC1155 already logs, but we add this to have the price information
        emit NFTsBurned(_id, msg.sender, _amount, fee);
    }

    /// @notice Withdraws the accrued platform fee
    function claimPlatformFee() external onlyOwner {
        uint256 amount = platformPool;
        platformPool = 0;
        SafeERC20.safeTransfer(token, msg.sender, amount);
        emit PlatformFeeClaimed(msg.sender, amount);
    }

    /// @notice Withdraws the accrued share creator fee
    /// @param _id ID of the share
    function claimCreatorFee(uint256 _id) public {
        require(shareData[_id].owner == msg.sender, "Not owner");
        uint256 amount = shareData[_id].shareCreatorPool;
        shareData[_id].shareCreatorPool = 0;
        SafeERC20.safeTransfer(token, msg.sender, amount);
        emit CreatorFeeClaimed(msg.sender, _id, amount);
    }

    /// @notice Changes the owner of a share
    /// @param _id ID of the share
    function changeShareOwner(uint256 _id, address _newOwner) external {
        require(shareData[_id].owner == msg.sender, "Not owner");
        shareData[_id].owner = _newOwner;
        emit ShareOwnerUpdated(_id, _newOwner);
    }

    /// @notice Withdraws the accrued share holder fee
    /// @param _id ID of the share
    function claimHolderFee(uint256 _id) public {
        uint256 amount = _getRewardsSinceLastClaim(_id);
        uint256 currRewardsLastClaimedValue = shareData[_id].shareHolderRewardsPerTokenScaled;
        rewardsLastClaimedValue[_id][msg.sender] = currRewardsLastClaimedValue;
        if (amount > 0) {
            SafeERC20.safeTransfer(token, msg.sender, amount);
        }
        emit HolderFeeClaimed(msg.sender, _id, amount, currRewardsLastClaimedValue);
    }

    /// @notice Withdraws the accrued share creator and share holder fee for multiple share IDs
    /// @param _creatorIds IDs of the shares for which the creator fee should be claimed
    /// @param _holderIds IDs of the shares for which the holder fee should be claimed
    function multiClaim(uint256[] calldata _creatorIds, uint256[] calldata _holderIds) external {
        for (uint256 i = 0; i < _creatorIds.length; i++) {
            claimCreatorFee(_creatorIds[i]);
        }
        for (uint256 i = 0; i < _holderIds.length; i++) {
            claimHolderFee(_holderIds[i]);
        }
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
        uint256 shareHolderFee = (_fee * HOLDER_CUT_BPS) / 10_000;
        uint256 shareCreatorFee = (_fee * CREATOR_CUT_BPS) / 10_000;
        uint256 platformFee = _fee - shareHolderFee - shareCreatorFee;
        shareData[_id].shareCreatorPool += shareCreatorFee;
        if (_tokenCount > 0) {
            shareData[_id].shareHolderRewardsPerTokenScaled += (shareHolderFee * 1e18) / _tokenCount;
        } else {
            // If there are no tokens in circulation, the fee goes to the platform
            platformFee += shareHolderFee;
        }
        platformPool += platformFee;
    }

    /// @notice Restricts or unrestricts share creation
    /// @param _isRestricted True if restricted, false if not
    function restrictShareCreation(bool _isRestricted) external onlyOwner {
        require(shareCreationRestricted != _isRestricted, "State already set");
        shareCreationRestricted = _isRestricted;
        emit ShareCreationRestricted(_isRestricted);
    }

    /// @notice Adds or removes an address from the whitelist of share creators
    /// @param _address Address to add or remove
    /// @param _isWhitelisted True if whitelisted, false if not
    function changeShareCreatorWhitelist(address _address, bool _isWhitelisted) external onlyOwner {
        require(whitelistedShareCreators[_address] != _isWhitelisted, "State already set");
        whitelistedShareCreators[_address] = _isWhitelisted;
    }

    /// @notice Allows to whitelist an address by a signature
    /// @param signature Signature that was obtained off-chain
    function changeShareCreatorWhitelistBySignature(bytes memory signature) external {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(keccak256("ShareCreator(address from)"), msg.sender)));
        address signer = ECDSA.recover(digest, signature);
        require(signer == offchainSigner);
        whitelistedShareCreators[msg.sender] = true;
    }

    /// @notice Change the address of the offchain signer for the share crator whitelist
    /// @param _newSigner New address to use as the offchain signer
    function changeOffchainSigner(address _newSigner) external onlyOwner {
        offchainSigner = _newSigner;
    }
}
