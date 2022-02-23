// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

contract Owners {
	event OwnerAdded(
		address indexed adder,
		address indexed owner,
		uint256 indexed timestamp
	);

	event OwnerRemoved(
		address indexed remover,
		address indexed removed,
		uint256 indexed timestamp
	);

	event OwnershipRenounced();

	bool public renounced;

	address private masterOwner;
	mapping(address => bool) private ownerMap;
	address[] private ownerList;

	constructor() {
		require(msg.sender != address(0), "Can't initialize with zero address");

		masterOwner = msg.sender;
		ownerMap[msg.sender] = true;
		ownerList.push(msg.sender);
	}

	modifier onlyOwners() {
		require(!renounced, "Ownership renounced");
		require(ownerMap[msg.sender], "Caller is not an owner");
		_;
	}

	function isOwner(address owner) public view returns (bool) {
		return ownerMap[owner];
	}

	function getOwners() external view returns (address[] memory) {
		return ownerList;
	}

	function addOwner(address owner) public onlyOwners {
		ownerMap[owner] = true;
		ownerList.push(owner);
		emit OwnerAdded(msg.sender, owner, block.timestamp);
	}

	function removeOwner(address owner) public onlyOwners {
		require(ownerMap[owner], "Address is not an owner");
		require(msg.sender != masterOwner, "Master owner can't be removed");

		uint256 lengthBefore = ownerList.length;
		for (uint256 i = 0; i < ownerList.length; i++) {
			if (ownerList[i] == owner) {
				ownerMap[owner] = false;
				for (uint256 j = i; j < ownerList.length - 1; j++) {
					ownerList[i] = ownerList[i + 1];
				}
				ownerList.pop();
				emit OwnerRemoved(msg.sender, owner, block.timestamp);
				break;
			}
		}
		uint256 lengthAfter = ownerList.length;
		require( // Sanity check
			lengthAfter < lengthBefore,
			"Something went wrong removing owners"
		);
	}

	function renounceOwnership() external {
		require(
			msg.sender == masterOwner,
			"Only master owner can renounce ownership"
		);

		renounced = true;
		emit OwnershipRenounced();
	}
}
