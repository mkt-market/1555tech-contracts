// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IasD {

    function mint(uint256 _amount) external;

    function burn(uint256 _amount) external;

    function withdrawCarry(uint256 _amount) external;
}
