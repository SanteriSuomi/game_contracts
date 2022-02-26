// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Rewards is PauseOwners {
	IERC20 token;
	address gameAddress;
	address nftAddress;

	constructor(
		address tokenAddress,
		address gameAddress_,
		address nftAddress_
	) {
		token = IERC20(tokenAddress);
		gameAddress = gameAddress_;
		nftAddress = nftAddress_;
	}

	modifier onlyInternalContracts() {
		require(msg.sender == gameAddress || msg.sender == nftAddress);
		_;
	}

	function withdraw(uint256 amountToken) external onlyInternalContracts {
		token.transfer(msg.sender, amountToken);
	}

	function setAddresses(
		address tokenAddress,
		address gameAddress_,
		address nftAddress_
	) external onlyOwners {
		token = IERC20(tokenAddress);
		gameAddress = gameAddress_;
		nftAddress = nftAddress_;
	}
}
