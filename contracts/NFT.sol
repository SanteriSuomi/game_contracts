// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./PauseOwners.sol";
import "./Token.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract NFT is ERC721, ERC721Enumerable, ERC721URIStorage, PauseOwners {
	using Counters for Counters.Counter;
	using Strings for uint256;

	event Minted(address minter, uint256 amount, uint256 date);
	event Compounded(address compounder, uint256 amount, uint256 date);
	event Claimed(address claimer, uint256 amount, uint256 date);

	uint256 public addressMax = 5;
	uint256 public supplyMax = 1000;
	uint256 public mintPrice = 1000; // Mint price of one NFT in tokens
	uint256 public maxTokenLevel = 10;
	uint256 public tokensPerLevel = 1000;
	uint256 public rewardDivisor = 10;
	mapping(uint256 => NFTData) public nftData;

	Token private token;
	string private nftBaseURI =
		"https://slimekeeper-web-dev.herokuapp.com/api/nft/data?";
	mapping(address => uint256) private amountMinted;
	Counters.Counter private tokenIds;

	// Represents in-game properties
	struct NFTData {
		uint256 level; // Current level of NFT
		uint256 birth; // Date this NFT was minted
		uint256 locked; // Tokens currently locked in this NFT
		uint256 claimed; // Date last rewards were last claimed, if not claimed once, same as birth

		// Other in-game properties here and API configured to show them
	}

	constructor() ERC721("NFT", "NFT") {}

	function mint(address to, uint256 amount) public checkPaused {
		require(totalSupply() < supplyMax, "Max supply has been reached");
		require(
			amountMinted[to] + amount <= addressMax,
			"Max mint exceeded for this address"
		);
		require(
			amountMinted[to] + amount <= supplyMax,
			"This mint would exceed supply cap"
		);
		uint256 totalMintPrice = (amount * mintPrice) * (10**18);
		require(token.balanceOf(to) >= totalMintPrice, "Token balance too low");
		require(
			token.allowance(to, address(this)) >= totalMintPrice,
			"Not enough allowance"
		);
		uint256 birth = block.timestamp;
		for (uint256 i = 0; i < amount; i++) {
			uint256 currTokenId = tokenIds.current();
			_safeMint(to, currTokenId);
			updateTokenUri(currTokenId, birth, 1, 0);
			nftData[currTokenId] = NFTData({
				level: 1,
				birth: birth,
				locked: 0,
				claimed: birth
			});
			tokenIds.increment();
		}
		amountMinted[to] += amount;
		token.transferFrom(to, address(this), totalMintPrice);
		emit Minted(to, amount, birth);
	}

	function compound(uint256 tokenId, uint256 amount) public checkPaused {
		uint256 tokenAmount = amount * (10**18);
		require(
			token.balanceOf(msg.sender) >= tokenAmount,
			"Token balance too low"
		);
		require(
			token.allowance(msg.sender, address(this)) >= tokenAmount,
			"Not enough allowance"
		);
		claim(tokenId); // Claim before compounding
		NFTData storage data = nftData[tokenId];
		require(data.level < maxTokenLevel, "This NFT is already max level");
		uint256 tokensPerLevelDec = tokensPerLevel * (10**18);
		uint256 newLocked = data.locked + tokenAmount;
		uint256 newLevel = newLocked / tokensPerLevelDec;
		uint256 excessAmount = 0;
		if (newLevel >= maxTokenLevel) {
			excessAmount = newLocked - (maxTokenLevel * tokensPerLevelDec);
			data.level = maxTokenLevel;
			data.locked = newLocked - excessAmount;
		} else {
			data.locked = newLocked;
			data.level = newLevel;
		}
		updateTokenUri(tokenId, data.level, data.birth, data.locked);
		token.transferFrom(
			msg.sender,
			address(this),
			tokenAmount - excessAmount
		);
	}

	function claim(uint256 tokenId) public checkPaused {
		require(_exists(tokenId), "This token ID does not exist");
		require(
			ownerOf(tokenId) == msg.sender,
			"Sender does not own this token"
		);
		NFTData storage data = nftData[tokenId];
		uint256 rewardAmount = (((block.timestamp - data.claimed) /
			rewardDivisor) * data.level) * (10**18);
		data.claimed = block.timestamp;
		require(
			token.balanceOf(address(this)) >= rewardAmount,
			"Not enough balance to withdraw"
		);
		token.transferFrom(address(this), msg.sender, rewardAmount);
	}

	function getNFTData(uint256 tokenId)
		public
		view
		returns (
			uint256,
			uint256,
			uint256,
			uint256
		)
	{
		require(_exists(tokenId), "This token ID does not exist");
		NFTData storage data = nftData[tokenId];
		return (data.level, data.birth, data.locked, data.claimed);
	}

	function setAddressMax(uint256 newMax) external onlyOwners {
		addressMax = newMax;
	}

	function setSupplyMax(uint256 newMax) external onlyOwners {
		supplyMax = newMax;
	}

	function setMaxTokenLevel(uint256 newLevel) external onlyOwners {
		mintPrice = newLevel;
	}

	function setMintPrice(uint256 newPrice) external onlyOwners {
		mintPrice = newPrice;
	}

	function setTokensPerLevel(uint256 newTokensPerLevel) external onlyOwners {
		tokensPerLevel = newTokensPerLevel;
	}

	function setRewardDivisor(uint256 newRewardDivisor) external onlyOwners {
		rewardDivisor = newRewardDivisor;
	}

	function setTokenAddress(address newTokenAddress) external onlyOwners {
		token = Token(newTokenAddress);
	}

	function setBaseUri(string memory newBaseURI) external onlyOwners {
		nftBaseURI = newBaseURI;
	}

	function totalSupply() public view override returns (uint256) {
		return tokenIds.current();
	}

	function _baseURI() internal view override returns (string memory) {
		return nftBaseURI;
	}

	function updateTokenUri(
		uint256 tokenId,
		uint256 level,
		uint256 birth,
		uint256 locked
	) private {
		_setTokenURI(
			tokenId,
			string(
				abi.encodePacked(
					"level=",
					level.toString(),
					"&birth=",
					birth.toString(),
					"&locked=",
					locked.toString()
				)
			)
		);
	}

	// The following functions are overrides required by Solidity.
	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 tokenId
	) internal override(ERC721, ERC721Enumerable) {
		super._beforeTokenTransfer(from, to, tokenId);
	}

	function _burn(uint256 tokenId)
		internal
		override(ERC721, ERC721URIStorage)
	{
		super._burn(tokenId);
	}

	function tokenURI(uint256 tokenId)
		public
		view
		override(ERC721, ERC721URIStorage)
		returns (string memory)
	{
		return super.tokenURI(tokenId);
	}

	function supportsInterface(bytes4 interfaceId)
		public
		view
		override(ERC721, ERC721Enumerable)
		returns (bool)
	{
		return super.supportsInterface(interfaceId);
	}
}
