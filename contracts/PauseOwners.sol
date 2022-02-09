// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./Owners.sol";

contract PauseOwners is Owners {
	bool internal isPaused;

	modifier checkPaused() {
		if (!isOwner(msg.sender)) {
			require(!isPaused, "Contract paused");
		}
		_;
	}

	function setIsPaused(bool newPaused) external onlyOwners {
		isPaused = newPaused;
	}
}
