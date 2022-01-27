// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SlimeNFT is ERC721URIStorage, Ownable {
    uint256 public maximumSupply;
    uint256 public currentSupply;
    bool public mintEnabled;
    bool public burnEnabled;

    constructor(uint256 _maximumSupply) ERC721("Slime", "SLM") {
        maximumSupply = _maximumSupply;
        currentSupply = 0;
        mintEnabled = false;
    }

    function mint(address toAddress, string memory tokenURI) public {
        require(currentSupply < maximumSupply, "supply exceeded");
        require(mintEnabled == true, "minting has not been enabled");
        _safeMint(toAddress, currentSupply);
        _setTokenURI(currentSupply, tokenURI);
        bool addSuccess;
        uint256 newCurrentSupply;
        (addSuccess, newCurrentSupply) = SafeMath.tryAdd(currentSupply, 1);
        currentSupply = newCurrentSupply;
        require(addSuccess == true, "something went wrong with incrementing current.");
    }

    function burn(uint256 tokenID) public {
        require(burnEnabled == true, "burn has not been enabled");
        _burn(tokenID);
        bool subSuccess;
        uint256 newCurrentSupply;
        (subSuccess, newCurrentSupply) = SafeMath.trySub(currentSupply, 1);
        currentSupply = newCurrentSupply;
        require(subSuccess == true, "something went wrong with incrementing current.");
    }

    function setMintEnabled(bool value) public onlyOwner {
        mintEnabled = value;
    }

    function setBurnEnabled(bool value) public onlyOwner {
        burnEnabled = value;
    }
}