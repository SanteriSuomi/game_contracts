// SPDX-License-Identifier: MIT
// @boughtthetopkms on Telegram

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "./Token.sol";

contract Rewards is PauseOwners {
	Token token;
	address gameAddress;
	address nftAddress;

	modifier onlyInternalContracts() {
		require(msg.sender == gameAddress || msg.sender == nftAddress);
		_;
	}

	function withdraw(address to, uint256 amountToken)
		external
		onlyInternalContracts
	{
		while (token.balanceOf(address(this)) < amountToken) {
			// Mints new supply for as long as needed
			token.emergencyMintRewards();
		}
		require(token.transfer(to, amountToken), "Token withdraw failed");
	}

	function setAddresses(
		address tokenAddress_,
		address gameAddress_,
		address nftAddress_
	) external onlyOwners {
		token = Token(payable(tokenAddress_));
		gameAddress = gameAddress_;
		nftAddress = nftAddress_;
	}
}
