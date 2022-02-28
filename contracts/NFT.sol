// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "./Token.sol";
import "./Rewards.sol";
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

	uint256 public addressMax = 5; // Max NFTs per address
	uint256 public supplyMax = 1000; // Max total supply cap
	uint256 public mintPrice = 100; // Mint price of one NFT in tokens
	uint256 public maxTokenLevel = 10; // Amount of levels an individual NFT can be upgraded
	uint256 public tokensPerLevel = 100; // Amount of tokens needed to upgrade an NFT (one level)
	uint256 public rewardDivisor = 690000000; // Divisor variable for affecting token generation rate

	bool public presaleEnded;
	bool public presalePaused = true;
	uint256 public presaleSupply = 500;
	uint256 public presalePrice = 500000000000000000; // 0.5

	Token private token;
	Rewards private rewards;

	Counters.Counter private tokenIds;

	string private nftBaseURI =
		"https://slimekeeper-web-dev.herokuapp.com/api/nft/data?";

	mapping(address => uint256) private amountMinted;
	mapping(uint256 => NFTData) private nftData; // Store NFT Data for invidividual token

	// Represents in-game properties
	struct NFTData {
		uint256 level; // Current level of NFT
		uint256 birthDate; // Date this NFT was minted
		uint256 lockedAmount; // Amount of tokens currently locked in this NFT
		uint256 lastClaimedDate; // Date last rewards were last claimed, if not claimed once, same as birth

		// Other in-game properties here and API configured to show them
	}

	constructor() ERC721("NFT", "NFT") {
		setIsPaused(true);
	}

	modifier checkPresaleState() {
		require(!presaleEnded, "Presale has ended already");
		require(!presalePaused, "Presale currently paused");
		_;
	}

	function mintPresale(address to, uint256 amount)
		external
		payable
		checkPresaleState
	{
		if (totalSupply() >= presaleSupply) {
			presaleEnded = true;
			return;
		}
		checkAmountMinted(to, amount, presaleSupply);
		uint256 totalMintPrice = amount * presalePrice;
		require(msg.value >= totalMintPrice, "Not enough ether sent");
		createNFT(to, amount);
		uint256 excess = msg.value - totalMintPrice; // Refund excess ether
		if (excess > 0) {
			(bool refundSuccess, ) = msg.sender.call{ value: excess }("");
			require(refundSuccess, "Refund unsuccessfull");
		}
	}

	function claimPresaleETH() external onlyOwners {
		// Allows contract owner to retrieve presale ether
		require(presaleEnded, "Presale not ended yet");
		(bool claimSuccess, ) = msg.sender.call{ value: address(this).balance }(
			""
		);
		require(claimSuccess, "Something went wrong claiming");
	}

	function mint(address to, uint256 amount) external checkPaused(msg.sender) {
		require(totalSupply() < supplyMax, "Max supply has been reached");
		checkAmountMinted(to, amount, supplyMax);
		uint256 totalMintPrice = amount * mintPrice * 10**token.decimals();
		require(
			token.balanceOf(msg.sender) >= totalMintPrice,
			"Token balance too low"
		);
		require(
			token.allowance(msg.sender, address(this)) >= totalMintPrice,
			"Not enough allowance"
		);
		createNFT(to, amount);
		require(
			token.transferFrom(msg.sender, address(rewards), totalMintPrice),
			"Token payment failed"
		);
	}

	function checkAmountMinted(
		address to,
		uint256 amount,
		uint256 supply
	) private view {
		require(
			amountMinted[to] + amount <= addressMax,
			"Max mint exceeded for this address"
		);
		require(
			amountMinted[to] + amount <= supply,
			"This mint would exceed presale supply cap"
		);
	}

	function createNFT(address to, uint256 amount) private {
		uint256 birthDate = block.timestamp;
		for (uint256 i = 0; i < amount; i++) {
			uint256 currTokenId = tokenIds.current();
			_safeMint(to, currTokenId);
			updateTokenUri(currTokenId, birthDate, 1, 0);
			nftData[currTokenId] = NFTData({
				level: 0,
				birthDate: birthDate,
				lockedAmount: 0,
				lastClaimedDate: birthDate
			});
			tokenIds.increment();
		}
		amountMinted[to] += amount;
		emit Minted(to, amount, birthDate);
	}

	function compound(uint256 tokenId, uint256 amountToken)
		external
		checkPaused(msg.sender)
	{
		amountToken *= 10**token.decimals();
		require(
			token.balanceOf(msg.sender) >= amountToken,
			"Token balance too low"
		);
		require(
			token.allowance(msg.sender, address(this)) >= amountToken,
			"Not enough allowance"
		);
		claimReward(tokenId); // Claim before compounding
		NFTData storage data = nftData[tokenId];
		require(data.level < maxTokenLevel, "This NFT is already max level");
		uint256 tokensPerLevelDecimals = tokensPerLevel * 10**token.decimals();
		uint256 newLocked = data.lockedAmount + amountToken;
		uint256 newLevel = newLocked / tokensPerLevelDecimals;
		uint256 excessAmount = 0;
		if (newLevel >= maxTokenLevel) {
			excessAmount = newLocked - (maxTokenLevel * tokensPerLevelDecimals);
			data.lockedAmount = newLocked - excessAmount;
			data.level = maxTokenLevel;
		} else {
			data.lockedAmount = newLocked;
			data.level = newLevel;
		}
		updateTokenUri(tokenId, data.level, data.birthDate, data.lockedAmount);
		uint256 finalAmountToken = amountToken - excessAmount;
		require(
			token.transferFrom(msg.sender, address(rewards), finalAmountToken),
			"Token payment failed"
		);
		emit Compounded(msg.sender, finalAmountToken, block.timestamp);
	}

	function updateTokenUri(
		uint256 tokenId,
		uint256 level,
		uint256 birthDate,
		uint256 lockedAmount
	) private {
		_setTokenURI(
			tokenId,
			string(
				abi.encodePacked(
					"level=",
					level.toString(),
					"&birthDate=",
					birthDate.toString(),
					"&lockedAmount=",
					lockedAmount.toString()
				)
			)
		);
	}

	function claimReward(uint256 tokenId) public checkPaused(msg.sender) {
		uint256 amountReward = getRewardAmount(tokenId);
		require(
			ownerOf(tokenId) == msg.sender,
			"Sender does not own this token"
		);
		if (amountReward > 0) {
			nftData[tokenId].lastClaimedDate = block.timestamp;
			rewards.withdraw(msg.sender, amountReward);
			emit Claimed(msg.sender, amountReward, block.timestamp);
		}
	}

	function getRewardAmount(uint256 tokenId) public view returns (uint256) {
		require(_exists(tokenId), "Token ID does not exist");
		NFTData storage data = nftData[tokenId];
		uint256 timeSinceLastClaim = block.timestamp - data.lastClaimedDate;
		return calculateReward(timeSinceLastClaim, data.level);
	}

	// Return the approximate APR considering certain level
	function approxAPR(uint256 level) external view returns (uint256) {
		return (calculateReward(365 days, level) * 100) / token.totalSupply();
	}

	function calculateReward(uint256 time, uint256 level)
		private
		view
		returns (uint256)
	{
		return (time * (level + 1) * token.totalSupply()) / rewardDivisor;
	}

	function getNFTData(uint256 tokenId)
		external
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
		return (
			data.level,
			data.birthDate,
			data.lockedAmount,
			data.lastClaimedDate
		);
	}

	function setAddressMax(uint256 newMax) external onlyOwners {
		addressMax = newMax;
	}

	function setSupplyMax(uint256 newMax) external onlyOwners {
		supplyMax = newMax;
	}

	function setMintPrice(uint256 newPrice) external onlyOwners {
		mintPrice = newPrice;
	}

	function setMaxTokenLevel(uint256 newLevel) external onlyOwners {
		mintPrice = newLevel;
	}

	function setTokensPerLevel(uint256 newTokensPerLevel) external onlyOwners {
		tokensPerLevel = newTokensPerLevel;
	}

	function setRewardDivisor(uint256 newRewardDivisor) external onlyOwners {
		rewardDivisor = newRewardDivisor;
	}

	function setPresalePaused(bool paused) external onlyOwners {
		presalePaused = paused;
	}

	function setPresaleEnded(bool ended) external onlyOwners {
		presaleEnded = ended;
	}

	function setPresaleSupply(uint256 supply) external onlyOwners {
		presaleSupply = supply;
	}

	function setPresalePrice(uint256 price) external onlyOwners {
		presalePrice = price;
	}

	function setAddresses(address tokenAddress, address rewardsAddress)
		external
		onlyOwners
	{
		token = Token(payable(tokenAddress));
		rewards = Rewards(rewardsAddress);
	}

	function setBaseUri(string memory baseURI_) external onlyOwners {
		nftBaseURI = baseURI_;
	}

	function totalSupply() public view override returns (uint256) {
		return tokenIds.current();
	}

	function _baseURI() internal view override returns (string memory) {
		return nftBaseURI;
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
