// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./PauseOwners.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20, PauseOwners {
	constructor(address gameAddress, address nftAddress) ERC20("Token", "TKN") {
		_mint(gameAddress, 1000 * (10**18));
		_mint(nftAddress, 1000 * (10**18));
	}
}
