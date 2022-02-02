// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./Owners.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract SlimeNFT is ERC721URIStorage, ERC721Enumerable, Owners {
    using Counters for Counters.Counter;
    using SafeMath for uint;

    struct MintedEvent {
        address minter;
        address to;
        uint amount;
        uint time;
    }
    event Minted(MintedEvent indexed mintedData);

    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _priceRangeCounter;

    bool public paused;
    uint public maxMint;

    string private __baseURI;
    mapping(address => uint) amountMinted;

    struct PriceRange {
        uint price;
		uint minted;
        uint cap;
    }
    PriceRange[] private _priceRanges;

    function getCurrentPriceRange() external view returns(uint, uint, uint) {
		uint currPriceRange = _priceRangeCounter.current();
		if (currPriceRange >= _priceRanges.length) {
			currPriceRange = currPriceRange.sub(1);
		}
		PriceRange storage priceRange = _priceRanges[currPriceRange];
        return (priceRange.price, priceRange.minted, priceRange.cap);
    }

    constructor(string memory baseURI, uint _maxMint, PriceRange[] memory priceRanges) ERC721("Slime", "SLM") {
        require(bytes(baseURI).length > 0, "Must set base URI");
        __baseURI = baseURI;
        maxMint = _maxMint;
        for(uint i = 0; i < priceRanges.length; i++) {
            _priceRanges.push(priceRanges[i]);
        }
    }

    modifier pauseCheck() {
        require(!paused || isOwner(msg.sender), "Minting is paused");
        _;
    }

    function mint(address to, uint amount, string memory _tokenURI) external payable pauseCheck {
		uint mintAmount = amountMinted[to] + amount;
		require(mintAmount <= maxMint, "Max mint amount reached");

		uint currPriceRange = _priceRangeCounter.current();
		require(currPriceRange < _priceRanges.length, "Supply cap reached");

		PriceRange storage priceRange = _priceRanges[currPriceRange];
		require(mintAmount <= priceRange.cap, "Amount exceeds current price range max");

		require(msg.value == (amount * priceRange.price * 10**18), "Ether sent is not correct");

		uint currTokenID = _tokenIdCounter.current();
		for(uint i = 0; i < amount; i++) {
			_safeMint(to, currTokenID);
			_setTokenURI(currTokenID, _tokenURI);
			_tokenIdCounter.increment();
			currTokenID = _tokenIdCounter.current();
			priceRange.minted = priceRange.minted.add(1);
			amountMinted[to] = amountMinted[to].add(1);
		}
		if (priceRange.minted >= priceRange.cap) {
			_priceRangeCounter.increment();
		}

        emit Minted(MintedEvent({
            minter: msg.sender,
            to: to,
            amount: amount,
            time: block.timestamp
        }));
    }

    function addPriceRange(PriceRange memory priceRange) external onlyOwners {
        require(priceRange.cap > 0, "Cap of 0 makes no sense");
        _priceRanges.push(priceRange);
    }

    // Return the current supply, not the capped max capped supply.
    function totalSupply() public view override returns(uint256) {
        return _tokenIdCounter.current();
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

    // Below are hooks that must be overridden because two or more parents contain them.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override (ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override (ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
}