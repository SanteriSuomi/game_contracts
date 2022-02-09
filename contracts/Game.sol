// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./PauseOwners.sol";
import "./NFT.sol";
import "./Token.sol";

contract Game is PauseOwners {
	NFT private nft;
	Token private token;

	function setNftAddress(address newNftAddress) external onlyOwners {
		nft = NFT(newNftAddress);
	}

	function setTokenAddress(address newTokenAddress) external onlyOwners {
		token = Token(newTokenAddress);
	}
}
