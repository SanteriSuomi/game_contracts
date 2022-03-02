// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./Owners.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract SlimeToken is ERC20, Owners {
	address private _nftAddress;
	IERC721 private _nft;

	constructor(uint256 initialSupply) ERC20("Slime", "SLM") {
		_mint(msg.sender, initialSupply);
	}

	function setNFT(address nftAddress) external onlyOwners {
		_nftAddress = nftAddress;
		_nft = IERC721(nftAddress);
	}
}
