// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract Token is ERC20, PauseOwners {
	uint256 public immutable MAX_TOTAL_FEE = 25; // We can never surpass this total fee

	bool public antiBotEnabled;
	bool private antiBotRanOnce; // We can only run antibot once, when initial liquidity is added
	uint256 private antiBotTaxesTimeInSeconds = 3600;
	uint256 private antiBotTaxesEndTime;
	uint256 private antiBotBlockTime = 2;
	uint256 private antiBotBlockEnd;

	mapping(address => bool) antiBotBlacklist;

	uint256 private antiBotSellDevelopmentTax = 10;
	uint256 private antiBotSellMarketingTax = 10;
	uint256 private antiBotSellLiquidityTax = 5;

	bool public liquidityTaxEnabled = true;
	bool public initialLiquidityAdded;
	uint256 private minBalanceToLiquify = 10;

	bool private inSwapAndLiquify;

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

	constructor(address gameAddress_, address nftAddress_)
		ERC20("Token", "TKN")
	{
		developmentAddress = payable(msg.sender);
		_mint(developmentAddress, 3333 * 10**decimals()); // For adding liquidity and team tokens
		_mint(gameAddress_, 3333 * 10**decimals()); // Used as game rewards
		_mint(nftAddress_, 3333 * 10**decimals()); // Used as NFT rewards
		isExcludedFromTax[gameAddress_] = true;
		isExcludedFromTax[nftAddress_] = true;
		isExcludedFromTax[address(this)] = true;
	}

	modifier lockSwapAndLiquify() {
		inSwapAndLiquify = true;
		_;
		inSwapAndLiquify = false;
	}

	receive() external payable {} // Must be defined so the contract is able to receive ETH from swaps

	function addLiquidity(uint256 amountToken) external payable onlyOwners {
		// Add initial liquidity and enabled the "anti-bot" feature
		address routerAddress = address(router);
		require(routerAddress != address(0), "Router not set yet");
		amountToken *= (10**decimals());
		require(
			balanceOf(msg.sender) >= amountToken,
			"Sender does not have enough token balance"
		);
		require(
			allowance(msg.sender, address(this)) >= amountToken,
			"Not enough allowance"
		);
		super._transfer(msg.sender, address(this), amountToken);
		approve(routerAddress, amountToken);
		// _approve(address(router), msg.sender, amountToken);
		router.addLiquidityETH{ value: msg.value }(
			address(this),
			amountToken,
			amountToken,
			msg.value,
			developmentAddress,
			block.timestamp + 1 hours
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
		// Initial liquidity transfer
		if (!initialLiquidityAdded && msg.sender == address(router)) {
			initialLiquidityAdded = true;
			_approve(sender, msg.sender, amount);
			super._transfer(sender, recipient, amount);
			return;
		}

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

		require(
			!antiBotBlacklist[sender] && !antiBotBlacklist[recipient],
			"Sender or recipient blacklisted"
		);

		bool takeFee = true;
		bool anyTaxAddressNotSet = developmentAddress == address(0) ||
			marketingAddress == address(0) ||
			liquidityAddress == address(0);
		bool isWalletToWalletTransfer = !Address.isContract(sender) &&
			!Address.isContract(recipient);

		if (
			isExcludedFromTax[sender] ||
			isExcludedFromTax[recipient] ||
			anyTaxAddressNotSet ||
			isWalletToWalletTransfer
		) {
			takeFee = false;
		}

		uint256 totalFeeInTokens = 0;
		if (takeFee) {
			address pair = UniswapV2Library.pairFor(
				router.factory(),
				address(this),
				router.WETH()
			);
			if (recipient == pair) {
				// Selling
				totalFeeInTokens = takeFees(
					sender,
					pair,
					amount,
					sellDevelopmentTax_,
					sellMarketingTax_,
					sellLiquidityTax_
				);
			} else {
				// Buying
				totalFeeInTokens = takeFees(
					sender,
					pair,
					amount,
					buyDevelopmentTax,
					buyMarketingTax,
					buyLiquidityTax
				);
			}
		}
		super._transfer(sender, recipient, amount - totalFeeInTokens);
	}

	function takeFees(
		address sender,
		address pair,
		uint256 amountToken,
		uint256 developmentFee,
		uint256 marketingFee,
		uint256 liquidityFee
	) private returns (uint256) {
		uint256 walletFeeInTokens = (amountToken *
			(developmentFee + marketingFee)) / 100;
		uint256 liquidityFeeInTokens = 0;
		if (liquidityTaxEnabled) {
			liquidityFeeInTokens = (amountToken * liquidityFee) / 100;
		}
		uint256 totalFeeInTokens = walletFeeInTokens + liquidityFeeInTokens;
		super._transfer(sender, address(this), totalFeeInTokens);

		swapAndTransferWalletFees(
			walletFeeInTokens,
			developmentFee,
			marketingFee
		);

		uint256 tokenBalance = balanceOf(address(this));
		if (
			liquidityTaxEnabled &&
			!inSwapAndLiquify &&
			sender != pair &&
			tokenBalance >= minBalanceToLiquify * (10**decimals())
		) {
			swapAndLiquify(tokenBalance);
		}

		return totalFeeInTokens;
	}

	function swapAndTransferWalletFees(
		uint256 amountToken,
		uint256 developmentFee,
		uint256 marketingFee
	) private {
		uint256 balance = swapTokensToETH(amountToken);
		if (balance > 0) {
			uint256 proportion = (balance * 100) /
				(developmentFee + marketingFee);
			uint256 devCut = (balance * developmentFee * proportion) / 10000;
			uint256 marCut = (balance * marketingFee * proportion) / 10000;

			(bool devSent, ) = developmentAddress.call{ value: devCut }("");
			(bool marSent, ) = marketingAddress.call{ value: marCut }("");
			require(devSent && marSent, "Couldn't transfer wallet fees");
		}
	}

	function swapAndLiquify(uint256 amountToken) private lockSwapAndLiquify {
		uint256 half1 = amountToken / 2;
		uint256 half2 = amountToken - half1;
		uint256 balanceBeforeSwap = address(this).balance;
		uint256 balanceAfterSwap = swapTokensToETH(half1); // Swap half of the tokens to BNB
		uint256 swapDifference = balanceAfterSwap - balanceBeforeSwap;
		addLiquidityTax(half2, swapDifference); // Add the non-swapped tokens and the swapped BNB to liquidity
	}

	function addLiquidityTax(uint256 amountToken, uint256 amountEth) private {
		// approve(address(router), amountToken);
		_approve(address(this), address(router), amountToken);
		router.addLiquidityETH{ value: amountEth }(
			address(this),
			amountToken,
			0,
			0,
			developmentAddress,
			block.timestamp + 1 minutes
		);
	}

	function swapTokensToETH(uint256 amountToken) private returns (uint256) {
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = router.WETH();
		// approve(address(router), amountToken);
		_approve(address(this), address(router), amountToken);
		router.swapExactTokensForETHSupportingFeeOnTransferTokens(
			amountToken,
			0, // Receive any amount
			path,
			address(this),
			block.timestamp + 1 minutes
		);
		return address(this).balance;
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
