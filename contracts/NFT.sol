// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "../abstract/AToken.sol";
import "../abstract/ARewards.sol";
import "../abstract/ANFT.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title Game NFT contract
/// @notice Is used as game characters but also acts as a reward generating node
contract NFT is ANFT {
	using Counters for Counters.Counter;
	using Strings for uint256;

	event Minted(address minter, uint256 amount, uint256 date);
	event Compounded(address compounder, uint256 amount, uint256 date);
	event Claimed(address claimer, uint256 amount, uint256 date);

	uint256 public addressMax = 5; // Max NFTs per address
	uint256 public supplyMax = 1000; // Max total supply cap
	uint256 public mintPrice = 100000000000000000000; // Mint price of one NFT in tokens
	uint256 public maxTokenLevel = 10; // Amount of levels an individual NFT can be upgraded
	uint256 public tokensPerLevel = 100000000000000000000; // Amount of tokens needed to upgrade an NFT (one level)
	uint256 public rewardRatePercentage = 500; // Reward rate in percentage per year (APR)

	bool public presaleEnded;
	bool public presalePaused = true;
	uint256 public presaleSupply = 100;
	uint256 public presalePrice = 0.5 ether;

	AToken private token;
	ARewards private rewards;

	Counters.Counter private tokenIds;

	string private nftBaseURI =
		"https://slimekeeper-web-dev.herokuapp.com/api/nft/data?";

	mapping(address => uint256) private amountMinted;
	mapping(uint256 => NFTData) private nftData; // Store NFT Data for individual token

	// Represents in-game properties
	struct NFTData {
		uint256 level; // Current level of NFT
		uint256 date; // Date this NFT was minted
		uint256 locked; // Amount of tokens currently locked in this NFT
		uint256 claimed; // Date last rewards were last claimed, if not claimed once, same as birth

		// TO:DO other game-specific fields?
	}

	constructor() ERC721("NFT", "NFT") {
		setIsPaused(true);
	}

	/// @notice Mint function for presale
	/// @param to Address to mint to
	/// @param amount Amount of NFTs to mint
	function mintPresale(address to, uint256 amount) external payable {
		require(!presaleEnded, "Presale has ended already");
		require(!presalePaused, "Presale currently paused");
		if (totalSupply() >= presaleSupply) {
			presaleEnded = true;
			return;
		}
		checkAmountMinted(to, amount, presaleSupply);
		uint256 totalMintPrice = amount * presalePrice;
		require(msg.value >= totalMintPrice, "Not enough ether sent");
		createNFT(to, amount);
		uint256 excess = msg.value - totalMintPrice;
		if (excess > 0) {
			// Refund excess ether
			(bool refundSuccess, ) = msg.sender.call{ value: excess }("");
			require(refundSuccess, "Refund unsuccessful");
		}
	}

	/// @notice Mint NFT using tokens
	/// @param to Address to mint to
	/// @param amount Amount of NFTs to mint
	function mint(address to, uint256 amount) external checkPaused(msg.sender) {
		require(totalSupply() < supplyMax, "Max supply has been reached");
		checkAmountMinted(to, amount, supplyMax);
		uint256 totalMintPrice = amount * mintPrice;
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
			"Token transfer failed"
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
		uint256 time = block.timestamp;
		for (uint256 i = 0; i < amount; i++) {
			uint256 tokenId = tokenIds.current();
			_safeMint(to, tokenId);
			NFTData memory data = NFTData({
				level: 1,
				date: time,
				locked: 0,
				claimed: time
			});
			nftData[tokenId] = data;
			updateTokenUri(tokenId, data);
			tokenIds.increment();
		}
		amountMinted[to] += amount;
		emit Minted(to, amount, time);
	}

	/// @notice Compound (lock) tokens in specific NFT and upgrades after every X amount of tokens compounded. Refunds excess if compounding over the max level
	/// @param tokenId ID of the token to compound (must be owner of said tokens)
	/// @param amountToken Amount of tokens to compound in the NFT
	function compound(uint256 tokenId, uint256 amountToken)
		external
		checkPaused(msg.sender)
	{
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
		uint256 newLocked = data.locked +
			amountToken +
			(data.level == 1 ? tokensPerLevel : 0);
		uint256 newLevel = newLocked / tokensPerLevel;
		uint256 amountExcess = 0;
		if (newLevel >= maxTokenLevel) {
			// If compounding amount excees max level
			amountExcess = newLocked - (maxTokenLevel * tokensPerLevel);
			data.locked = newLocked - amountExcess;
			data.level = maxTokenLevel;
		} else {
			data.locked = newLocked;
			data.level = newLevel;
		}
		updateTokenUri(tokenId, data);
		amountToken -= amountExcess;
		require(
			token.transferFrom(msg.sender, address(rewards), amountToken),
			"Token transfer failed"
		);
		emit Compounded(msg.sender, amountToken, block.timestamp);
	}

	function updateTokenUri(uint256 tokenId, NFTData memory data) private {
		_setTokenURI(
			tokenId,
			string(
				abi.encodePacked(
					"level=",
					data.level.toString(),
					"&date=",
					data.date.toString(),
					"&locked=",
					data.locked.toString(),
					"&claimed=",
					data.claimed.toString()
				)
			)
		);
	}

	/// @notice Claim NFT rewards
	/// @param tokenId ID of the NFT of whose rewards to claim
	function claimReward(uint256 tokenId) public checkPaused(msg.sender) {
		uint256 amountReward = getRewardAmount(tokenId);
		require(
			ownerOf(tokenId) == msg.sender,
			"Sender does not own this token"
		);
		if (amountReward > 0) {
			nftData[tokenId].claimed = block.timestamp;
			rewards.withdrawReward(msg.sender, amountReward);
			emit Claimed(msg.sender, amountReward, block.timestamp);
		}
	}

	/// @notice Check amount of claimable rewards for this token (this function does not claim them)
	/// @param tokenId ID of the NFT of whose rewards to claim
	/// @return Amount of rewards this NFT is entitled to claim
	function getRewardAmount(uint256 tokenId) public view returns (uint256) {
		require(_exists(tokenId), "Token ID does not exist");
		NFTData storage data = nftData[tokenId];
		uint256 timeSinceLastClaim = block.timestamp - data.claimed;
		return calculateReward(timeSinceLastClaim, data.level);
	}

	/// @notice Calculate how many rewards could get in some time (seconds)
	/// @param time Time in seconds
	/// @param tokenLvl Level of NFT
	/// @return Amount of rewards this NFT is entitled to claim
	function calculateReward(uint256 time, uint256 tokenLvl)
		public
		view
		returns (uint256)
	{
		time = (time * 10**token.decimals()) / 365 days; // Time in seconds to years
		return tokenLvl * rewardRatePercentage * time;
	}

	/// @notice Allows team to claim presale money
	function claimPresaleETH() external onlyOwners {
		// Allows contract owner to retrieve presale ether
		require(presaleEnded, "Presale not ended yet");
		(bool claimSuccess, ) = msg.sender.call{ value: address(this).balance }(
			""
		);
		require(claimSuccess, "Something went wrong claiming");
	}

	/// @notice Return data for specific NFT
	/// @param tokenId ID of the NFT
	/// @return Return the data of NFT such as level, date of birth, locked token amount, last reward claim date
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
		return (data.level, data.date, data.locked, data.claimed);
	}

	function setAddressMax(uint256 addressMax_) external onlyOwners {
		addressMax = addressMax_;
	}

	function setSupplyMax(uint256 supplyMax_) external onlyOwners {
		supplyMax = supplyMax_;
	}

	function setMintPrice(uint256 mintPrice_) external onlyOwners {
		mintPrice = mintPrice_;
	}

	function setMaxTokenLevel(uint256 maxTokenLevel_) external onlyOwners {
		maxTokenLevel = maxTokenLevel_;
	}

	function setTokensPerLevel(uint256 tokensPerLevel_) external onlyOwners {
		tokensPerLevel = tokensPerLevel_;
	}

	function setRewardRatePercentage(uint256 rewardRatePercentage_)
		external
		onlyOwners
	{
		rewardRatePercentage = rewardRatePercentage_;
	}

	function setPresaleEnded(bool presaleEnded_) external onlyOwners {
		presaleEnded = presaleEnded_;
	}

	function setPresalePaused(bool presalePaused_) external onlyOwners {
		presalePaused = presalePaused_;
	}

	function setPresaleSupply(uint256 presaleSupply_) external onlyOwners {
		presaleSupply = presaleSupply_;
	}

	function setPresalePrice(uint256 presalePrice_) external onlyOwners {
		presalePrice = presalePrice_;
	}

	function setToken(address tokenAddress_) external onlyOwners {
		token = AToken(tokenAddress_);
	}

	function setRewards(address rewardsAddress_) external onlyOwners {
		rewards = ARewards(rewardsAddress_);
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
}
