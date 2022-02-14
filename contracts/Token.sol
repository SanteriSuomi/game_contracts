// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./PauseOwners.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

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

	mapping(address => bool) public isExcludedFromTax;

	IUniswapV2Router02 private router;

	constructor(address gameAddress, address nftAddress) ERC20("Token", "TKN") {
		developmentAddress = payable(msg.sender);
		_mint(developmentAddress, 1000 * (10**18)); // For adding liquidity
		_mint(gameAddress, 1000 * (10**18)); // Used as game rewards
		_mint(nftAddress, 1000 * (10**18)); // Used as NFT rewards
		isExcludedFromTax[gameAddress] = true;
		isExcludedFromTax[nftAddress] = true;
	}

	receive() external payable {} // Must be defined so the contract is able to receive ETH from swaps

	function addLiquidity(uint256 amountToken) public payable onlyOwners {
		require(address(router) != address(0), "Router not set yet");
		router.addLiquidityETH{ value: msg.value }(
			address(this),
			amountToken,
			0,
			0,
			developmentAddress,
			block.timestamp
		);
	}

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
			isExcludedFromTax[sender] ||
			anyTaxAddressNotSet ||
			isWalletToWalletTransfer
		) {
			takeFee = false;
		}

		if (takeFee) {
			uint256 totalFee = 0;
			if (recipient == routerAddress) {
				// Selling
				totalFee =
					sellDevelopmentTax +
					sellMarketingTax +
					sellLiquidityTax;
				takeFees(
					amount,
					totalFee,
					sellDevelopmentTax,
					sellMarketingTax,
					sellLiquidityTax
				);
			} else {
				// Buying
				totalFee =
					buyDevelopmentTax +
					buyMarketingTax +
					buyLiquidityTax;
				takeFees(
					amount,
					totalFee,
					buyDevelopmentTax,
					buyMarketingTax,
					buyLiquidityTax
				);
			}
		}
		super._transfer(sender, recipient, amount - finalFee);
	}

	function takeFees(
		uint256 amountToken,
		uint256 totalFee,
		uint256 developmentFee,
		uint256 marketingFee,
		uint256 liquidityFee
	) private returns (uint256) {
		uint256 walletFeeInTokens = (tokenAmount *
			(developmentFee + marketingFee)) / 100;
		uint256 balance = swapTokensToETH(walletFeeInTokens);
		if (balance > 0) {
			(bool devSent, ) = developmentAddress.call{
				value: getEthAmountFromFee(balance, developmentFee, walletFee)
			}("");
			(bool marSent, ) = marketingAddress.call{
				value: getEthAmountFromFee(balance, marketingFee, walletFee)
			}("");
			require(
				devSent && marSent,
				"Couldn't send to either development or marketing address"
			);
		}
		uint256 liquidityFeeInTokens = (tokenAmount * liquidityFee) / 100;
		uint256 tokenPrice = getTokenPrice(liquidityFeeInTokens);
		return feeInTokens;
	}

	function addTaxLiquidity(uint256 amountToken, uint256 amountEth) private {
		_approve(address(this), address(router), amountToken);
		router.addLiquidityETH{ value: amountEth }(
			address(this),
			amountToken,
			0,
			0,
			developmentAddress,
			block.timestamp
		);
	}

	function getTokenPrice(uint256 amountToken) private {
		address factoryAddress = router.factory();
		address pairAddress = UniswapV2Library.pairFor(
			factoryAddress,
			address(this),
			router.WETH()
		);
		require(
			pairAddress != address(0),
			"Can't add tax liquidity yet, initial liquidity has not been provided"
		);
		(uint256 res0, uint256 res1) = UniswapV2Library.getReserves(
			factoryAddress,
			address(this),
			router.WETH()
		);
		return UniswapV2Library.quote(amountToken, res0, res1);
	}

	function swapTokensToETH(uint256 amountTokens) private returns (uint256) {
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = router.WETH();
		_approve(address(this), address(router), amountIn);
		router.swapExactTokensForETH(
			amountTokens,
			0, // Receive any amount
			path,
			address(this),
			block.timestamp
		);
		return address(this).balance; // Balance in wei after taking fees
	}

	function getEthAmountFromFee(
		uint256 weiBalance,
		uint256 fee,
		uint256 totalFee
	) private pure returns (uint256) {
		return (weiBalance * totalFee * fee) / 100;
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
		isExcludedFromTax[address_] = true;
	}

	function removeTaxExcludedAddress(address address_) external onlyOwners {
		isExcludedFromTax[address_] = false;
	}

	function setRouter(address routerAddress) external onlyOwners {
		router = IUniswapV2Router02(routerAddress);
	}
}
