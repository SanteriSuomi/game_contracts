// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./PauseOwners.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract Token is ERC20, PauseOwners {
	uint256 public immutable MAX_FEE = 25;

	uint256 public sellDevelopmentTax = 4;
	uint256 public sellMarketingTax = 4;
	uint256 public sellLiquidityTax = 2;

	uint256 public buyDevelopmentTax = 2;
	uint256 public buyMarketingTax = 2;
	uint256 public buyLiquidityTax = 1;

	address payable public developmentAddress;
	address payable public marketingAddress;
	address payable public liquidityAddress;

	mapping(address => bool) public isExludedFromTax;

	IUniswapV2Router02 private router;

	constructor(address gameAddress, address nftAddress) ERC20("Token", "TKN") {
		_mint(gameAddress, 1000 * (10**18)); // Mint tokens to game address to be used as game rewards
		_mint(nftAddress, 1000 * (10**18)); // Mint tokens to NFT address to be used as NFT rewards
		isExludedFromTax[gameAddress] = true;
		isExludedFromTax[nftAddress] = true;
	}

	receive() external payable {} // Must be defined so the contract is able to receive ETH from swaps

	function _transfer(
		address sender,
		address recipient,
		uint256 amount
	) internal virtual override {
		address routerAddress = address(router);

		bool takeFee = true;
		bool anyTaxAddressNotSet = developmentAddress == address(0) ||
			marketingAddress == address(0) ||
			liquidityAddress == address(0);
		bool isWalletToWalletTransfer = !(sender == routerAddress &&
			recipient == routerAddress);
		if (
			isExludedFromTax[sender] ||
			anyTaxAddressNotSet ||
			isWalletToWalletTransfer
		) {
			takeFee = false;
		}

		uint256 totalFee = 0;
		if (takeFee) {
			if (recipient == routerAddress) {
				// Selling
				totalFee =
					sellDevelopmentTax +
					sellMarketingTax +
					sellLiquidityTax;
				takeFees(
					totalFee,
					sellDevelopmentTax,
					sellMarketingTax,
					sellLiquidityTax
				);
			} else if (sender == routerAddress) {
				// Buying
			}
		}

		super._transfer(sender, recipient, amount);
	}

	function takeFees(
		uint256 totalFee,
		uint256 developmentFee,
		uint256 marketingFee,
		uint256 liquidityFee
	) private {
		uint256 balance = swapTokensToETH(totalFee);
		if (balance > 0) {
			uint256 developmentAmount = getEthAmountFromFee(
				balance,
				developmentFee,
				totalFee
			);
			uint256 marketingAmount = getEthAmountFromFee(
				balance,
				marketingFee,
				totalFee
			);
			(bool devSent, bytes memory devData) = developmentAddress.call{
				value: developmentAmount
			}("");
			(bool marSent, bytes memory marData) = marketingAddress.call{
				value: marketingAmount
			}("");
			require(
				devSent && marSent,
				"Couldn't sent to either development or marketing address"
			);
		}
	}

	function swapTokensToETH(uint256 amountIn) private returns (uint256) {
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = router.WETH();
		_approve(address(this), address(router), amountIn);
		router.swapExactTokensForETH(
			amountIn,
			0, // Receive any amount
			path,
			address(this),
			block.timestamp
		);
		return address(this).balance; // Balance in ETH after taking fees
	}

	function getEthAmountFromFee(
		uint256 ethBalance,
		uint256 fee,
		uint256 totalFee
	) private pure returns (uint256) {
		return (ethBalance * totalFee * fee) / 100;
	}

	function setSellTaxes(
		uint256 sellDevelopmentTax_,
		uint256 sellMarketingTax_,
		uint256 sellLiquidityTax_
	) external onlyOwners {
		require(
			(sellDevelopmentTax_ + sellMarketingTax_ + sellLiquidityTax_) <=
				MAX_FEE,
			"Total taxes are above the allowed amount"
		);
		sellDevelopmentTax = sellDevelopmentTax_;
		sellMarketingTax = sellMarketingTax_;
		sellLiquidityTax = sellDevelopmentTax_;
	}

	function setBuyTaxes(
		uint256 buyDevelopmentTax_,
		uint256 buyMarketingTax_,
		uint256 buyLiquidityTax_
	) external onlyOwners {
		require(
			(buyDevelopmentTax_ + buyMarketingTax_ + buyLiquidityTax_) <=
				MAX_FEE,
			"Total taxes are above the allowed amount"
		);
		buyDevelopmentTax = buyDevelopmentTax_;
		buyMarketingTax = buyMarketingTax_;
		buyLiquidityTax = buyLiquidityTax_;
	}

	function setTaxAddresses(
		address developmentAddress_,
		address marketingAddress_,
		address liquidityAddress_
	) external onlyOwners {
		require(
			!(developmentAddress_ == address(0) ||
				marketingAddress_ == address(0) ||
				liquidityAddress_ == address(0)),
			"None of the addresses can't be zero addresses"
		);
		developmentAddress = payable(developmentAddress_);
		marketingAddress = payable(marketingAddress_);
		liquidityAddress = payable(liquidityAddress_);
	}

	function addTaxExcludedAddress(address address_) external onlyOwners {
		isExludedFromTax[address_] = true;
	}

	function removeTaxExcludedAddress(address address_) external onlyOwners {
		isExludedFromTax[address_] = false;
	}

	function setRouter(address routerAddress) external onlyOwners {
		router = IUniswapV2Router02(routerAddress);
	}
}
