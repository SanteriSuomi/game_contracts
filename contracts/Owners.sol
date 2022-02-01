// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

contract Owners {
    event OwnerAdded(address indexed adder, address indexed owner, uint indexed timestamp);
    event OwnerRemoved(address indexed remover, address indexed removed, uint indexed timestamp);

    mapping(address => bool) private _ownerMap;
    address[] private _ownerList;

    function isOwner(address owner) public view returns(bool) {
        return _ownerMap[owner];
    }

    function getOwners() external view returns (address[] memory) {
        return _ownerList;
    }

    constructor() {
        require(msg.sender != address(0), "Can't initialize with zero address");
        _ownerMap[msg.sender] = true;
        _ownerList.push(msg.sender);
    }

    modifier onlyOwners() {
        require(_ownerMap[msg.sender] == true, "Caller is not an owner");
        _;
    }

    function addOwner(address owner) external onlyOwners {
        _ownerMap[owner] = true;
        _ownerList.push(owner);
        emit OwnerAdded(msg.sender, owner, block.timestamp);
    }

    function removeOwner(address owner) external onlyOwners {
        require(_ownerMap[owner] == true, "Address is not an owner");
        for(uint i = 0; i < _ownerList.length; i++) {
            if (_ownerList[i] == owner) {
                _ownerMap[owner] = false;
                for (uint j = i; j < _ownerList.length - 1; j++) {
	                _ownerList[i] = _ownerList[i + 1];
                }
                _ownerList.pop();
                emit OwnerRemoved(msg.sender, owner, block.timestamp);
                break;
            }
        }
    }
}