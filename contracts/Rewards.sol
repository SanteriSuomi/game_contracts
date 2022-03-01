// SPDX-License-Identifier: MIT
// @boughtthetopkms on Telegram

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "./Token.sol";

contract Rewards is PauseOwners {
	event Withdraw(address to, uint256 amount, address caller);

	Token token;
	address gameAddress;
	address nftAddress;

	function withdraw(address to, uint256 amountToken) external {
		require(msg.sender == gameAddress || msg.sender == nftAddress);
		while (token.balanceOf(address(this)) < amountToken) {
			// Mints new supply for as long as needed
			token.emergencyMintRewards();
		}
		require(token.transfer(to, amountToken), "Token withdraw failed");
		emit Withdraw(to, amountToken, msg.sender);
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
