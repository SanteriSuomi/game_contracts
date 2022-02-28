// SPDX-License-Identifier: MIT
// @boughtthetopkms on Telegram

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "./NFT.sol";
import "./Token.sol";

contract Game is PauseOwners {
	NFT private nft;
	Token private token;

	function setAddresses(address nftAddress, address tokenAddress)
		external
		onlyOwners
	{
		nft = NFT(payable(nftAddress));
		token = Token(payable(tokenAddress));
	}
}
