// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "../contracts/PauseOwners.sol";

/// @title Abstract class representing game rewards pool
/// @dev To improve modularity, so we don't have to hardcode the contract itself
abstract contract ARewards is PauseOwners {
	function withdrawReward(address to, uint256 amountToken) external virtual;
}
