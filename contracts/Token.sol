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
	uint256 private minBalanceToSwapAndTransfer;

	bool private inSwapAndTransfer;

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
	IUniswapV2Pair private pair;

	constructor(address gameAddress_, address nftAddress_)
		ERC20("Token", "TKN")
	{
		developmentAddress = payable(msg.sender);
		_mint(developmentAddress, 3333 * 10**decimals()); // For adding liquidity and team tokens
		_mint(gameAddress_, 3333 * 10**decimals()); // Used as game rewards
		_mint(nftAddress_, 3333 * 10**decimals()); // Used as NFT rewards
		minBalanceToSwapAndTransfer = totalSupply() / 100; // If contract balance is min 1% of total supply, can sell for BNB
		isExcludedFromTax[gameAddress_] = true;
		isExcludedFromTax[nftAddress_] = true;
		isExcludedFromTax[address(this)] = true;
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
		router.addLiquidityETH{ value: msg.value }(
			address(this),
			amountToken,
			amountToken,
			msg.value,
			developmentAddress,
			block.timestamp + 1 hours
		);
		initialLiquidityAdded = true;
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
		if (
			!initialLiquidityAdded &&
			msg.sender == address(router) &&
			tx.origin == developmentAddress
		) {
			//Initial liquidity transfer
			_approve(sender, msg.sender, amount);
			super._transfer(sender, recipient, amount);
			return;
		} else if (!initialLiquidityAdded) {
			revert("Initial liquidity not added");
		}

		if (amount == 0) {
			super._transfer(sender, recipient, 0);
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

		uint256 totalTax = 0;
		uint256 developmentTax = 0;
		uint256 marketingTax = 0;
		uint256 liquidityTax = 0;

		uint256 tokenBalance = balanceOf(address(this));
		if (
			!inSwapAndTransfer &&
			tokenBalance >= (minBalanceToSwapAndTransfer * 10**18) &&
			sender != address(pair)
		) {
			inSwapAndTransfer = true;

			totalTax =
				sellDevelopmentTax_ +
				sellMarketingTax_ +
				sellLiquidityTax_;
			developmentTax = (tokenBalance * sellDevelopmentTax_) / totalTax;
			marketingTax = (tokenBalance * sellMarketingTax_) / totalTax;
			liquidityTax = (tokenBalance * sellLiquidityTax_) / totalTax;

			uint256 ethBalance = swapTokensToETH(developmentTax + marketingTax);
			uint256 ethForDevelopment = (ethBalance * developmentTax) /
				(developmentTax + marketingTax);
			uint256 ethForMarketing = (ethBalance * marketingTax) /
				(developmentTax + marketingTax);

			(bool devSuccess, ) = developmentAddress.call{
				value: ethForDevelopment
			}("");
			(bool marSuccess, ) = marketingAddress.call{
				value: ethForMarketing
			}("");

			swapAndLiquify(liquidityTax);

			inSwapAndTransfer = false;

			require(
				devSuccess && marSuccess,
				"Couldn't send to development or marketing wallet"
			);
		}

		totalTax = 0;
		developmentTax = 0;
		marketingTax = 0;
		liquidityTax = 0;

		bool takeFee = !inSwapAndTransfer &&
			!isExcludedFromTax[sender] &&
			!isExcludedFromTax[recipient];

		if (takeFee) {
			if (recipient == address(pair)) {
				// Selling
				developmentTax = (amount * sellDevelopmentTax_) / 100;
				marketingTax = (amount * sellMarketingTax_) / 100;
				liquidityTax = (amount * sellLiquidityTax_) / 100;
			} else if (sender == address(pair)) {
				// Buying
				developmentTax = (amount * buyDevelopmentTax) / 100;
				marketingTax = (amount * buyMarketingTax) / 100;
				liquidityTax = (amount * buyLiquidityTax) / 100;
			}
			totalTax = developmentTax + marketingTax + liquidityTax;

			if (totalTax > 0) {
				super._transfer(sender, address(this), totalTax);
				amount -= totalTax;
			}
		}

		super._transfer(sender, recipient, amount);
	}

	function swapAndLiquify(uint256 amountToken) private {
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
		pair = IUniswapV2Pair(
			IUniswapV2Factory(router.factory()).createPair(
				address(this),
				router.WETH()
			)
		);
	}
}
