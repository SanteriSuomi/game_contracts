// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/PauseOwners.sol";

/// @title Abstract class representing game token
abstract contract AToken is ERC20, PauseOwners {
	function emergencyMint() external virtual;
}
