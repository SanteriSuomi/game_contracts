// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "../abstract/AToken.sol";
import "../abstract/ARewards.sol";

/// @title Game token pool with associated functions
/// @notice Holds all the tokens used by the game
contract Rewards is ARewards {
	event WithdrawReward(address to, uint256 amount, address caller);

	AToken token;
	address gameAddress;
	address nftAddress;

	/// @notice Withdraw tokens from the pool
	/// @param to Address to which tokens will be withdrawn to
	/// @param amountToken Amount of tokens to withdraw
	/// @dev Will mint tokens if rewards pool is empty. Only usable by in-game contracts
	function withdrawReward(address to, uint256 amountToken) external override {
		require(msg.sender == gameAddress || msg.sender == nftAddress);
		while (token.balanceOf(address(this)) < amountToken) {
			token.emergencyMint();
		}
		require(token.transfer(to, amountToken), "Token withdraw failed");
		emit WithdrawReward(to, amountToken, msg.sender);
	}

	function setAddresses(
		address tokenAddress_,
		address gameAddress_,
		address nftAddress_
	) external onlyOwners {
		token = AToken(tokenAddress_);
		gameAddress = gameAddress_;
		nftAddress = nftAddress_;
	}
}
