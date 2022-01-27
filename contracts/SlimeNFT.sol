// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract SlimeNFT is ERC721URIStorage, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    uint256 public maximumSupply;
    Counters.Counter private _tokenIds;

    bool public mintEnabled;
    bool public burnEnabled;
    string public baseTokenURI;

    function setMintEnabled(bool value) public onlyOwner {
        mintEnabled = value;
    }

    function setBurnEnabled(bool value) public onlyOwner {
        burnEnabled = value;
    }

    function updateBaseTokenURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    function _baseURI() internal view override returns(string memory) {
        return baseTokenURI;
    }

    constructor(uint256 _maximumSupply, string memory _baseTokenURI) ERC721("Slime", "SLM") {
        maximumSupply = _maximumSupply;
        baseTokenURI = _baseTokenURI;
        mintEnabled = false;
        burnEnabled = false;
    }

    function mint(address toAddress, string memory _tokenURI) public {
        require(_tokenIds.current() < maximumSupply, "supply exceeded");
        require(mintEnabled == true, "minting has not been enabled");
        uint256 _newTokenID = _tokenIds.current();
        _safeMint(toAddress, _newTokenID);
        _setTokenURI(_newTokenID, _tokenURI);
        _tokenIds.increment();
    }

    function burn(uint256 tokenID) public {
        require(burnEnabled == true, "burn has not been enabled");
        require(_exists(tokenID), "this tokenID does not exist");
        _burn(tokenID);
        _tokenIds.decrement();
    }

    // Below here are overridden functions that have not been modified.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
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

    function safeMint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
    }
}