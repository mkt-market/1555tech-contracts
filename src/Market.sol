// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Turnstile} from "../interface/Turnstile.sol";

contract Market is ERC1155, Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Bonding curves that can be used for shares
    mapping(address => bool) whitelistedBondingCurves;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event BondingCurveStateChange(address indexed curve, bool isWhitelisted);

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
}
