// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

contract Token is ERC20, PauseOwners {
	uint256 public immutable MAX_TOTAL_FEE = 25; // We can never surpass this total fee

	bool public antiBotEnabled = false;
	bool private antiBotRanOnce = false; // We can only run antibot once, when initial liquidity is added
	uint256 private antiBotTaxesTimeInSeconds = 3600;
	uint256 private antiBotTaxesEndTime;
	uint256 private antiBotBlockTime = 2;
	uint256 private antiBotBlockEnd;

	mapping(address => bool) antiBotBlacklist;

	uint256 private antiBotSellDevelopmentTax = 10;
	uint256 private antiBotSellMarketingTax = 10;
	uint256 private antiBotSellLiquidityTax = 5;

	bool public liquidityTaxEnabled = true;

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
		_mint(developmentAddress, 3333 * 10**decimals()); // For adding liquidity and team tokens
		_mint(gameAddress, 3333 * 10**decimals()); // Used as game rewards
		_mint(nftAddress, 3333 * 10**decimals()); // Used as NFT rewards
		isExcludedFromTax[gameAddress] = true;
		isExcludedFromTax[nftAddress] = true;
	}

	receive() external payable {} // Must be defined so the contract is able to receive ETH from swaps

	function addLiquidityAntiBot(
		uint256 amountToken,
		uint256 amountTokenMin,
		uint256 amountETHmin
	) public payable onlyOwners {
		// Add initial liquidity and enabled the "anti-bot" feature
		require(address(router) != address(0), "Router not set yet");
		require(
			balanceOf(msg.sender) >= amountToken,
			"Sender does not have enough token balance"
		);
		router.addLiquidityETH{ value: msg.value }(
			address(this),
			amountToken,
			amountTokenMin,
			amountETHmin,
			developmentAddress,
			block.timestamp
		);
		if (!antiBotRanOnce) {
			antiBotEnabled = true;
			antiBotRanOnce = true;
			antiBotTaxesEndTime = block.timestamp + antiBotTaxesTimeInSeconds;
			antiBotBlockEnd = block.number + antiBotBlockTime;
		}
	}

	function _transfer(
		address sender,
		address recipient,
		uint256 amount
	) internal virtual override checkPaused {
		// Temporary local variables for setting antibot taxes
		uint256 sellDevelopmentTax_ = sellDevelopmentTax;
		uint256 sellMarketingTax_ = sellMarketingTax;
		uint256 sellLiquidityTax_ = sellLiquidityTax;

		if (antiBotEnabled) {
			if (block.number <= antiBotBlockEnd) {
				antiBotBlacklist[sender] = true;
			}
			if (block.timestamp <= antiBotTaxesEndTime) {
				sellDevelopmentTax_ = antiBotSellDevelopmentTax;
				sellMarketingTax_ = antiBotSellMarketingTax;
				sellLiquidityTax_ = antiBotSellLiquidityTax;
			} else {
				antiBotEnabled = false;
			}
		}

		if (!antiBotBlacklist[sender]) {
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

			uint256 totalFeeInTokens = 0;
			if (takeFee) {
				if (recipient == routerAddress) {
					// Selling
					totalFeeInTokens = takeFees(
						amount,
						sellDevelopmentTax_,
						sellMarketingTax_,
						sellLiquidityTax_
					);
				} else {
					// Buying
					totalFeeInTokens = takeFees(
						amount,
						buyDevelopmentTax,
						buyMarketingTax,
						buyLiquidityTax
					);
				}
			}
			super._transfer(sender, recipient, amount - totalFeeInTokens);
		}
	}

	function takeFees(
		uint256 amountToken,
		uint256 developmentFee,
		uint256 marketingFee,
		uint256 liquidityFee
	) private returns (uint256) {
		uint256 totalFee = developmentFee + marketingFee + liquidityFee;

		uint256 walletFeeInTokens = (amountToken *
			(developmentFee + marketingFee)) / 100;
		swapAndTransferFees(
			walletFeeInTokens,
			totalFee,
			developmentFee,
			marketingFee
		);

		uint256 liquidityFeeInTokens = 0;
		if (liquidityTaxEnabled) {
			liquidityFeeInTokens = (amountToken * liquidityFee) / 100;
			swapAndLiquify(liquidityFeeInTokens);
		}

		return walletFeeInTokens + liquidityFeeInTokens;
	}

	function swapAndTransferFees(
		uint256 amountToken,
		uint256 totalFee,
		uint256 developmentFee,
		uint256 marketingFee
	) private {
		uint256 balance = swapTokensToETH(amountToken);
		if (balance > 0) {
			// No point in trying to send if swapped 0
			(bool devSent, ) = developmentAddress.call{
				value: getEthFromBalanceWithFees(
					balance,
					totalFee,
					developmentFee + marketingFee
				)
			}("");
			(bool marSent, ) = marketingAddress.call{
				value: getEthFromBalanceWithFees(
					balance,
					totalFee,
					marketingFee
				)
			}("");
			require(
				devSent && marSent,
				"Couldn't send to either development or marketing address"
			);
		}
	}

	function getEthFromBalanceWithFees(
		uint256 balance,
		uint256 withFee,
		uint256 totalFees
	) private pure returns (uint256) {
		return (balance * withFee * totalFees) / 100;
	}

	function swapAndLiquify(uint256 amountToken) private {
		uint256 half1 = amountToken / 2;
		uint256 half2 = amountToken - half1;
		uint256 balanceBeforeSwap = address(this).balance;
		uint256 balanceAfterSwap = swapTokensToETH(half1); // Swap half of the tokens to BNB
		addTaxLiquidity(half2, balanceAfterSwap - balanceBeforeSwap); // Add the non-swapped tokens and the swapped BNB to liquidity
	}

	function swapTokensToETH(uint256 amountToken) private returns (uint256) {
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = router.WETH();
		_approve(address(this), address(router), amountToken);
		router.swapExactTokensForETH(
			amountToken,
			0, // Receive any amount
			path,
			address(this),
			block.timestamp
		);
		return address(this).balance; // Balance in wei after taking fees
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

	function setSellTaxes(
		uint256 sellDevelopmentTax_,
		uint256 sellMarketingTax_,
		uint256 sellLiquidityTax_
	) external onlyOwners {
		require(
			(sellDevelopmentTax_ + sellMarketingTax_ + sellLiquidityTax_) <=
				MAX_TOTAL_FEE,
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
				MAX_TOTAL_FEE,
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

	function removeBlacklist(address address_) external onlyOwners {
		antiBotBlacklist[address_] = false;
	}

	function setLiquidityTaxEnabled(bool enabled) external onlyOwners {
		liquidityTaxEnabled = enabled;
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
