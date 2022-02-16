// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

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
		token = Token(payable(newTokenAddress));
	}
}
