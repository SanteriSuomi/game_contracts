// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "./abstract/AToken.sol";
import "./abstract/ANFT.sol";
import "./abstract/AGame.sol";

contract Game is AGame {
	AToken private token;
	ANFT private nft;

	function setToken(address tokenAddress_) external onlyOwners {
		token = AToken(tokenAddress_);
	}

	function setNFT(address nftAddress_) external onlyOwners {
		nft = ANFT(nftAddress_);
	}
}
