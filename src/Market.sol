// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Turnstile} from "../interface/Turnstile.sol";

contract Market is ERC1155, Ownable2Step {
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

    /// @notice Whitelist or remove whitelist for a bonding curve
    /// @param _bondingCurve Address of the bonding curve
    /// @param _newState True if whitelisted, false if not
    function changeBondingCurveAllowed(address _bondingCurve, bool _newState) external onlyOwner {
        require(whitelistedBondingCurves[_bondingCurve] != _newState, "State already set");
        whitelistedBondingCurves[_bondingCurve] = _newState;
        emit BondingCurveStateChange(_bondingCurve, _newState);
    }

    function createNewShare(string memory _shareName, address _bondingCurve) external returns (uint256 id) {
        require(whitelistedBondingCurves[_bondingCurve], "Bonding curve not whitelisted");
        require(shareIDs[_shareName] == 0, "Share already exists");
        id = ++shareCount;
        shareIDs[_shareName] = id;
        shareBondingCurves[id] = _bondingCurve;
        emit ShareCreated(id, _shareName, _bondingCurve);
    }
}
