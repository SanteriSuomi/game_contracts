// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "./abstract/AToken.sol";
import "./abstract/ARewards.sol";

/// @title Game token pool with associated functions
/// @notice Holds all the tokens used by the game
contract Rewards is ARewards {
	event Withdrew(address to, uint256 amount, address caller);

	AToken token;
	address gameAddress;
	address nftAddress;

	/// @notice Withdraw tokens from the pool
	/// @param to Address to which tokens will be withdrawn to
	/// @param amountToken Amount of tokens to withdraw
	function withdrawReward(address to, uint256 amountToken) external override {
		require(msg.sender != address(0), "Not callable by zero address");
		require(
			msg.sender == gameAddress || msg.sender == nftAddress,
			"Only callable by internal contracts"
		);
		while (token.balanceOf(address(this)) < amountToken) {
			token.emergencyMint();
		}
		require(token.transfer(to, amountToken), "Token withdraw failed");
		emit Withdrew(to, amountToken, msg.sender);
	}

	function setToken(address tokenAddress_) external onlyOwners {
		token = AToken(tokenAddress_);
	}

	function setAddresses(address gameAddress_, address nftAddress_)
		external
		onlyOwners
	{
		gameAddress = gameAddress_;
		nftAddress = nftAddress_;
	}
}
