// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "../PauseOwners.sol";

/// @title Abstract class representing game rewards pool
abstract contract ARewards is PauseOwners {
	function withdrawReward(address to, uint256 amountToken) external virtual;
}
