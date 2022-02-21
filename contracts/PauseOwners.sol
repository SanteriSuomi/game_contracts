// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./Owners.sol";

contract PauseOwners is Owners {
	bool public isPaused = false;

	modifier checkPaused() {
		if (!isOwner(msg.sender)) {
			require(!isPaused, "Contract paused");
		}
		_;
	}

	function setIsPaused(bool newPaused) public onlyOwners {
		isPaused = newPaused;
	}
}
