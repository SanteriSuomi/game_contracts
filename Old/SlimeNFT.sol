// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./Owners.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SlimeNFT is ERC721URIStorage, ERC721Enumerable, Owners {
	using Counters for Counters.Counter;
	using SafeMath for uint256;
	using Strings for uint256;

	struct MintedEvent {
		address minter;
		address to;
		uint256 amount;
		uint256 time;
	}
	event Minted(MintedEvent indexed mintedData);
	event Compounded(
		address indexed compounder,
		uint256 indexed tokenID,
		uint256 indexed amount
	);

	Counters.Counter private _tokenIdCounter;
	Counters.Counter private _priceRangeCounter;

	address private _tokenAddress;
	IERC20 private _token;

	bool public paused;
	uint256 public maxMint;

	string private __baseURI;
	mapping(address => uint256) amountMinted;

	bool public whitelistEnabled;
	bytes32 private merkleRoot;

	struct PriceRange {
		uint256 price;
		uint256 minted;
		uint256 cap;
	}
	PriceRange[] private _priceRanges;

	function getCurrentPriceRange()
		external
		view
		returns (
			uint256,
			uint256,
			uint256
		)
	{
		uint256 currPriceRange = _priceRangeCounter.current();
		if (currPriceRange >= _priceRanges.length) {
			currPriceRange = currPriceRange.sub(1);
		}
		PriceRange storage priceRange = _priceRanges[currPriceRange];
		return (priceRange.price, priceRange.minted, priceRange.cap);
	}

	uint256 private _maxLevel = 10;
	uint256 private _tokensPerLevel = 50;
	struct SlimeInfo {
		uint256 amountCompounded;
		uint256 level;
		uint256 time;
	}
	mapping(uint256 => SlimeInfo) public slimeInfo;

	constructor(
		string memory baseURI,
		uint256 _maxMint,
		PriceRange[] memory priceRanges
	) ERC721("Slime", "SLM") {
		require(bytes(baseURI).length > 0, "Must set base URI");
		__baseURI = baseURI;
		maxMint = _maxMint;
		for (uint256 i = 0; i < priceRanges.length; i++) {
			_priceRanges.push(priceRanges[i]);
		}
		_tokenIdCounter.increment();
	}

	modifier pauseCheck() {
		require(!paused || isOwner(msg.sender), "Minting is paused");
		_;
	}

	function mint(
		address to,
		uint256 amount,
		string memory _tokenURI,
		bytes32[] calldata merkleProof
	) external payable pauseCheck {
		if (whitelistEnabled) {
			bytes32 merkleLeaf = keccak256(abi.encodePacked(to));
			require(
				MerkleProof.verify(merkleProof, merkleRoot, merkleLeaf),
				"This address is not whitelisted"
			);
		}

		uint256 mintAmount = amountMinted[to] + amount;
		require(mintAmount <= maxMint, "Max mint amount reached");

		uint256 currPriceRange = _priceRangeCounter.current();
		require(currPriceRange < _priceRanges.length, "Supply cap reached");

		PriceRange storage priceRange = _priceRanges[currPriceRange];
		require(
			mintAmount <= priceRange.cap,
			"Amount exceeds current price range max"
		);

		require(
			msg.value == (amount * priceRange.price * 10**18),
			"Ether sent is not correct"
		);

		uint256 currTokenID = _tokenIdCounter.current();
		for (uint256 i = 0; i < amount; i++) {
			_safeMint(to, currTokenID);
			_setTokenURI(currTokenID, _tokenURI);
			_tokenIdCounter.increment();
			currTokenID = _tokenIdCounter.current();
			slimeInfo[currTokenID] = SlimeInfo({
				amountCompounded: 0,
				level: 1,
				time: block.timestamp
			});
			priceRange.minted = priceRange.minted.add(1);
			amountMinted[to] = amountMinted[to].add(1);
		}
		if (priceRange.minted >= priceRange.cap) {
			_priceRangeCounter.increment();
		}

		emit Minted(
			MintedEvent({
				minter: msg.sender,
				to: to,
				amount: amount,
				time: block.timestamp
			})
		);
	}

	function compound(uint256 amount, uint256 tokenID) public {
		require(
			amount <= _token.balanceOf(msg.sender),
			"Token balance not high enough to compound"
		);
		require(
			amount <= _token.allowance(msg.sender, address(this)),
			"Increase contract spend allowance"
		);
		require(
			_exists(tokenID) && msg.sender == ownerOf(tokenID),
			"This NFT does not exist or you do not own it"
		);
		SlimeInfo storage info = slimeInfo[tokenID];
		require(info.level < _maxLevel, "This NFT is already max level");
		info.amountCompounded = info.amountCompounded.add(amount);
		info.level = info.amountCompounded.div(_tokensPerLevel);
		info.time = block.timestamp;
		uint256 excess = 0;
		if (info.level >= _maxLevel) {
			excess = info.amountCompounded - (_maxLevel * _tokensPerLevel);
			info.level = _maxLevel;
			info.amountCompounded = info.amountCompounded.sub(excess);
		}
		_setTokenURI(
			tokenID,
			string(
				abi.encodePacked(
					"level=",
					info.level.toString(),
					"&locked=",
					info.amountCompounded.toString()
				)
			)
		);
		_token.transferFrom(msg.sender, address(this), amount.sub(excess));
		emit Compounded(msg.sender, tokenID, amount);
	}

	function setMaxLevel(uint256 maxLevel) external onlyOwners {
		_maxLevel = maxLevel;
	}

	function setToken(address tokenAddress) external onlyOwners {
		_tokenAddress = tokenAddress;
		_token = IERC20(tokenAddress);
	}

	function addPriceRange(PriceRange memory priceRange) external onlyOwners {
		require(priceRange.cap > 0, "Cap of 0 makes no sense");
		_priceRanges.push(priceRange);
	}

	// Return the current supply, not the capped max capped supply.
	function totalSupply() public view override returns (uint256) {
		return _tokenIdCounter.current().sub(1);
	}

	function setPaused(bool _paused) external onlyOwners {
		paused = _paused;
	}

	function _baseURI() internal view virtual override returns (string memory) {
		return __baseURI;
	}

	function setBaseURI(string memory baseURI) external onlyOwners {
		__baseURI = baseURI;
	}

	function setMaxMint(uint256 _maxMint) external onlyOwners {
		maxMint = _maxMint;
	}

	function setMerkleRoot(bytes32 _merkleRoot) external onlyOwners {
		merkleRoot = _merkleRoot;
	}

	function setWhitelistEnabled(bool enabled) external onlyOwners {
		whitelistEnabled = enabled;
	}

	// Below are hooks that must be overridden because two or more parents contain them.
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

	function supportsInterface(bytes4 interfaceId)
		public
		view
		virtual
		override(ERC721, ERC721Enumerable)
		returns (bool)
	{
		return super.supportsInterface(interfaceId);
	}

	function tokenURI(uint256 tokenId)
		public
		view
		virtual
		override(ERC721, ERC721URIStorage)
		returns (string memory)
	{
		return super.tokenURI(tokenId);
	}
}
