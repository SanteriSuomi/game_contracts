// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./PauseOwners.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20, PauseOwners {
	constructor(address gameAddress, address nftAddress) ERC20("Token", "TKN") {
		_mint(gameAddress, 1000 * (10**18));
		_mint(nftAddress, 1000 * (10**18));
	}

	function _transfer(
		address sender,
		address recipient,
		uint256 amount
	) internal virtual override {
		if (
			!_midSwap &&
			!hasRole(EXCLUDED, sender) &&
			!hasRole(EXCLUDED, recipient)
		) {
			uint256 taxAmount = (amount * _tax) / _DIV;
			super._transfer(sender, _thisAddress, taxAmount);
			amount -= taxAmount;
		}
		super._transfer(sender, recipient, amount);
	}
}
