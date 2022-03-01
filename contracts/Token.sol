// SPDX-License-Identifier: MIT
// @boughtthetopkms on Telegram

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "./Rewards.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

contract Token is ERC20, PauseOwners {
	event LiquidityAdded(
		address sender,
		uint256 amountETH,
		uint256 amountToken
	);

	uint256 public immutable MAX_TOTAL_FEE = 2500; // We can never surpass this total fee

	bool private antiBotEnabled;
	bool private antiBotRanOnce; // We can only run antibot once, when initial liquidity is added
	uint256 private antiBotTaxesStartTime; // When when antibot taxes start
	uint256 private antiBotTaxesEndTime; // Time when antibot taxes end
	uint256 private antiBotBlockEndBlock; // Block when antibot blacklister no longer works
	uint256 private antiBotTaxesTimeInSeconds = 3600;
	uint256 private antiBotBlockTimeInBlocks = 2;
	uint256 private antiBotMaxTX = 100000000000000000000; // 1% percent of the supply

	uint256 public antiBotSellDevelopmentTax = 900;
	uint256 public antiBotSellMarketingTax = 900;
	uint256 public antiBotSellRewardsTax = 400;
	uint256 public antiBotSellLiquidityTax = 300;

	mapping(address => bool) public antiBotBlacklist;

	bool public liquidityTaxEnabled = true;

	uint256 private minBalanceForSwapAndTransfer = 10000000000000000000;
	bool private inSwapAndTransfer;

	uint256 public sellDevelopmentTax = 300;
	uint256 public sellMarketingTax = 300;
	uint256 public sellRewardsTax = 400;
	uint256 public sellLiquidityTax = 200;

	uint256 public buyDevelopmentTax = 200;
	uint256 public buyMarketingTax = 200;
	uint256 public buyRewardsTax = 200;
	uint256 public buyLiquidityTax = 100;

	address payable public developmentAddress;
	address payable public marketingAddress;
	address payable public rewardsAddress;
	address payable public gameAddress;
	address payable public nftAddress;

	mapping(address => bool) public isExcludedFromTax;

	uint256 private emergencyMintDivisor = 50;

	IUniswapV2Router02 private router;
	IUniswapV2Pair private pair;

	constructor(
		address gameAddress_,
		address nftAddress_,
		address rewardsAddress_,
		address marketingAddress_,
		address routerAddress_
	) ERC20("Token", "TKN") {
		setIsPaused(true);
		developmentAddress = payable(msg.sender);
		marketingAddress = payable(marketingAddress_);
		rewardsAddress = payable(rewardsAddress_);
		gameAddress = payable(gameAddress_);
		nftAddress = payable(nftAddress_);
		_mint(developmentAddress, 3333 * 10**decimals()); // For adding liquidity and team tokens
		_mint(rewardsAddress, 6667 * 10**decimals()); // Game + NFT rewards
		isExcludedFromTax[developmentAddress] = true;
		isExcludedFromTax[marketingAddress] = true;
		isExcludedFromTax[rewardsAddress] = true;
		isExcludedFromTax[gameAddress] = true;
		isExcludedFromTax[nftAddress] = true;
		isExcludedFromTax[address(this)] = true;
		createRouterPair(routerAddress_);
	}

	modifier lockSwapAndTransfer() {
		inSwapAndTransfer = true;
		_;
		inSwapAndTransfer = false;
	}

	modifier onlyInternalContracts() {
		require(msg.sender == rewardsAddress);
		_;
	}

	function _transfer(
		address sender,
		address recipient,
		uint256 amount
	) internal virtual override checkPaused(tx.origin) {
		(
			uint256 sellDevelopmentTax_,
			uint256 sellMarketingTax_,
			uint256 sellLiquidityTax_,
			uint256 sellRewardsTax_,
			bool guardActivated
		) = antiBotGuard(sender, recipient, amount);
		if (guardActivated) {
			return;
		}

		if (amount == 0) {
			super._transfer(sender, recipient, 0);
			return;
		}

		bool notExcludedFromTax = !isExcludedFromTax[sender] &&
			!isExcludedFromTax[recipient];
		uint256 tokenBalance = balanceOf(address(this));
		if (
			!inSwapAndTransfer &&
			tokenBalance >= minBalanceForSwapAndTransfer &&
			recipient == address(pair) && // Is a sell
			notExcludedFromTax
		) {
			swapAndTransfer(
				tokenBalance,
				sellDevelopmentTax_,
				sellMarketingTax_,
				sellLiquidityTax_
			);
		}

		bool takeFee = !inSwapAndTransfer && notExcludedFromTax;
		if (takeFee) {
			uint256[] memory taxes = new uint256[](4); // Need to do this abomination because otherwise solidity compiler screams
			taxes[0] = sellDevelopmentTax_;
			taxes[1] = sellMarketingTax_;
			taxes[2] = sellLiquidityTax_;
			taxes[3] = sellRewardsTax_;
			amount = takeFees(amount, sender, recipient, taxes);
		}

		super._transfer(sender, recipient, amount);
	}

	function antiBotGuard(
		address sender,
		address recipient,
		uint256 amount
	)
		private
		returns (
			uint256 sellDevelopmentTax_,
			uint256 sellMarketingTax_,
			uint256 sellLiquidityTax_,
			uint256 sellRewardsTax_,
			bool guardActivated
		)
	{
		sellDevelopmentTax_ = sellDevelopmentTax;
		sellMarketingTax_ = sellMarketingTax;
		sellLiquidityTax_ = sellLiquidityTax;
		sellRewardsTax_ = sellRewardsTax;
		if (!isOwner(tx.origin)) {
			require(
				!antiBotBlacklist[sender] && !antiBotBlacklist[recipient],
				"Sender or recipient blacklisted"
			);
			if (antiBotEnabled) {
				require(
					amount <= antiBotMaxTX,
					"Transaction exceeded max amount"
				);
				if (block.number <= antiBotBlockEndBlock) {
					antiBotBlacklist[sender] = true;
					guardActivated = true;
				} else if (block.timestamp <= antiBotTaxesEndTime) {
					uint256 timePassed = 1 +
						block.timestamp -
						antiBotTaxesStartTime;
					sellDevelopmentTax_ = scaleToRangeAndReverse(
						timePassed,
						1,
						antiBotTaxesTimeInSeconds,
						sellDevelopmentTax,
						antiBotSellDevelopmentTax
					);
					sellMarketingTax_ = scaleToRangeAndReverse(
						timePassed,
						1,
						antiBotTaxesTimeInSeconds,
						sellMarketingTax,
						antiBotSellMarketingTax
					);
					sellLiquidityTax_ = scaleToRangeAndReverse(
						timePassed,
						1,
						antiBotTaxesTimeInSeconds,
						sellLiquidityTax,
						antiBotSellLiquidityTax
					);
					sellRewardsTax_ = scaleToRangeAndReverse(
						timePassed,
						1,
						antiBotTaxesTimeInSeconds,
						sellRewardsTax,
						antiBotSellRewardsTax
					);
				} else {
					antiBotEnabled = false;
				}
			}
		}
	}

	function scaleToRangeAndReverse(
		// Helper function which scales a value to a range and reverses it
		uint256 x, // Value to scale
		uint256 minX, // Minimum value of x
		uint256 maxX, // Maximum value of X
		uint256 a, // Range start
		uint256 b // Range end
	) private pure returns (uint256) {
		return (a + b) - ((b - a) * ((x - minX) / (maxX - minX)) + a);
	}

	function takeFees(
		uint256 amount,
		address sender,
		address recipient,
		uint256[] memory sellTaxes
	) private returns (uint256) {
		uint256 totalTax = 0;
		uint256 developmentTax = 0;
		uint256 marketingTax = 0;
		uint256 liquidityTax = 0;
		uint256 rewardsTax = 0;

		if (recipient == address(pair)) {
			// Selling
			developmentTax = (amount * sellTaxes[0]) / 10000;
			marketingTax = (amount * sellTaxes[1]) / 10000;
			liquidityTax = (amount * sellTaxes[2]) / 10000;
			rewardsTax = (amount * sellTaxes[3]) / 10000;
		} else if (sender == address(pair)) {
			// Buying
			developmentTax = (amount * buyDevelopmentTax) / 10000;
			marketingTax = (amount * buyMarketingTax) / 10000;
			liquidityTax = (amount * buyLiquidityTax) / 10000;
			rewardsTax = (amount * buyRewardsTax) / 10000;
		}
		totalTax = developmentTax + marketingTax + liquidityTax + rewardsTax;

		if (totalTax > 0) {
			super._transfer(sender, address(this), totalTax);
			super._transfer(address(this), rewardsAddress, rewardsTax);
			amount -= totalTax;
		}
		return amount;
	}

	function swapAndTransfer(
		uint256 tokenBalance,
		uint256 sellDevelopmentTax_,
		uint256 sellMarketingTax_,
		uint256 sellLiquidityTax_
	) private lockSwapAndTransfer {
		uint256 totalTax = sellDevelopmentTax_ + sellMarketingTax_;
		if (liquidityTaxEnabled) {
			totalTax += sellLiquidityTax_;
		}
		uint256 developmentTax = (tokenBalance * sellDevelopmentTax_) /
			totalTax;
		uint256 marketingTax = (tokenBalance * sellMarketingTax_) / totalTax;

		swapAndTransferFees(developmentTax, marketingTax);

		if (liquidityTaxEnabled) {
			uint256 liquidityTax = (tokenBalance * sellLiquidityTax_) /
				totalTax;
			swapAndLiquify(liquidityTax);
		}
	}

	function swapAndTransferFees(uint256 developmentTax, uint256 marketingTax)
		private
	{
		uint256 totalTax = developmentTax + marketingTax;
		uint256 ethBalance = swapTokensToETH(totalTax);
		uint256 ethForDevelopment = (ethBalance * developmentTax) / totalTax;
		uint256 ethForMarketing = (ethBalance * marketingTax) / totalTax;

		(bool developmentSuccess, ) = developmentAddress.call{
			value: ethForDevelopment
		}("");
		(bool marketingSuccess, ) = marketingAddress.call{
			value: ethForMarketing
		}("");

		require(
			developmentSuccess && marketingSuccess,
			"Couldn't send to development or marketing wallet"
		);
	}

	function swapAndLiquify(uint256 amountToken) private {
		uint256 half1Token = amountToken / 2;
		uint256 half2Token = amountToken - half1Token;
		uint256 balanceBeforeSwapETH = address(this).balance;
		uint256 balanceAfterSwapETH = swapTokensToETH(half2Token); // Swap half of the tokens to BNB
		uint256 swapDifferenceETH = balanceAfterSwapETH - balanceBeforeSwapETH;
		addLiquidity(swapDifferenceETH, half1Token); // Add the non-swapped tokens and the swapped BNB to liquidity
	}

	function addLiquidity(uint256 amountETH, uint256 amountToken) private {
		_approve(address(this), address(router), amountToken);
		router.addLiquidityETH{ value: amountETH }(
			address(this),
			amountToken,
			0,
			0,
			developmentAddress,
			block.timestamp + 1 minutes
		);
		emit LiquidityAdded(tx.origin, amountETH, amountToken);
	}

	function swapTokensToETH(uint256 amountToken) private returns (uint256) {
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = router.WETH();
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

	function createRouterPair(address routerAddress) private {
		router = IUniswapV2Router02(routerAddress);
		pair = IUniswapV2Pair(
			IUniswapV2Factory(router.factory()).createPair(
				address(this),
				router.WETH()
			)
		);
		isExcludedFromTax[address(router)] = true;
	}

	// This function is only to be used by the rewards contract when the rewards pool no longer has rewards
	function emergencyMintRewards() external onlyInternalContracts {
		uint256 amountToMint = totalSupply() / emergencyMintDivisor; // Default: 2% of the supply
		super._mint(rewardsAddress, amountToMint);
	}

	function addInitialLiquidity(uint256 amountToken)
		external
		payable
		onlyOwners
	{
		// Add initial liquidity and enabled the "anti-bot" feature
		address routerAddress = address(router);
		require(routerAddress != address(0), "Router not set yet");
		require(
			balanceOf(msg.sender) >= amountToken,
			"Sender does not have enough token balance"
		);
		require(
			allowance(msg.sender, address(this)) >= amountToken,
			"Not enough allowance given to the contract"
		);
		_approve(msg.sender, routerAddress, amountToken);
		super._transfer(msg.sender, address(this), amountToken);
		addLiquidity(msg.value, amountToken);
	}

	function activateTradeWithAntibot() external onlyOwners {
		require(!antiBotRanOnce, "Antibot has already been ran");
		antiBotEnabled = true;
		antiBotRanOnce = true;
		antiBotTaxesStartTime = block.timestamp;
		antiBotTaxesEndTime = antiBotTaxesStartTime + antiBotTaxesTimeInSeconds;
		antiBotBlockEndBlock = block.number + antiBotBlockTimeInBlocks;
		setIsPaused(false);
	}

	function setAntiBotSellTaxes(
		uint256 sellDevelopmentTax_,
		uint256 sellMarketingTax_,
		uint256 sellLiquidityTax_,
		uint256 sellRewardsTax_
	) external onlyOwners {
		require(antiBotEnabled, "Antibot period has passed");
		require(
			(sellDevelopmentTax_ +
				sellMarketingTax_ +
				sellLiquidityTax_ +
				sellRewardsTax_) <= MAX_TOTAL_FEE,
			"Total taxes are above the allowed amount"
		);
		antiBotSellDevelopmentTax = sellDevelopmentTax_;
		antiBotSellMarketingTax = sellMarketingTax_;
		antiBotSellLiquidityTax = sellLiquidityTax_;
		antiBotSellRewardsTax = sellRewardsTax_;
	}

	function setSellTaxes(
		uint256 sellDevelopmentTax_,
		uint256 sellMarketingTax_,
		uint256 sellLiquidityTax_,
		uint256 sellRewardsTax_
	) external onlyOwners {
		require(
			(sellDevelopmentTax_ +
				sellMarketingTax_ +
				sellLiquidityTax_ +
				sellRewardsTax_) <= MAX_TOTAL_FEE,
			"Total taxes are above the allowed amount"
		);
		sellDevelopmentTax = sellDevelopmentTax_;
		sellMarketingTax = sellMarketingTax_;
		sellLiquidityTax = sellLiquidityTax_;
		sellRewardsTax = sellRewardsTax_;
	}

	function setBuyTaxes(
		uint256 buyDevelopmentTax_,
		uint256 buyMarketingTax_,
		uint256 buyLiquidityTax_,
		uint256 buyRewardsTax_
	) external onlyOwners {
		require(
			(buyDevelopmentTax_ +
				buyMarketingTax_ +
				buyLiquidityTax_ +
				buyRewardsTax_) <= MAX_TOTAL_FEE,
			"Total taxes are above the allowed amount"
		);
		buyDevelopmentTax = buyDevelopmentTax_;
		buyMarketingTax = buyMarketingTax_;
		buyLiquidityTax = buyLiquidityTax_;
		buyRewardsTax = buyRewardsTax_;
	}

	function setTaxAddresses(
		address developmentAddress_,
		address marketingAddress_,
		address rewardsAddress_
	) external onlyOwners {
		require(
			!(developmentAddress_ == address(0) ||
				marketingAddress_ == address(0) ||
				rewardsAddress_ == address(0)),
			"None of the addresses can't be zero addresses"
		);
		developmentAddress = payable(developmentAddress_);
		marketingAddress = payable(marketingAddress_);
		rewardsAddress = payable(rewardsAddress_);
		isExcludedFromTax[developmentAddress] = true;
		isExcludedFromTax[marketingAddress] = true;
		isExcludedFromTax[rewardsAddress] = true;
	}

	function setRouter(address routerAddress) external onlyOwners {
		createRouterPair(routerAddress);
	}

	function setInternalAddresses(address gameAddress_, address nftAddress_)
		external
		onlyOwners
	{
		gameAddress = payable(gameAddress_);
		nftAddress = payable(nftAddress_);
		isExcludedFromTax[gameAddress] = true;
		isExcludedFromTax[nftAddress] = true;
	}

	function removeBlacklistedAddress(address address_) external onlyOwners {
		antiBotBlacklist[address_] = false;
	}

	function setLiquidityTaxEnabled(bool liquidityTaxEnabled_)
		external
		onlyOwners
	{
		liquidityTaxEnabled = liquidityTaxEnabled_;
	}

	function addTaxExcludedAddress(address address_) external onlyOwners {
		isExcludedFromTax[address_] = true;
	}

	function removeTaxExcludedAddress(address address_) external onlyOwners {
		isExcludedFromTax[address_] = false;
	}

	function setEmergencyMintDivisor(uint256 emergencyMintDivisor_)
		external
		onlyOwners
	{
		emergencyMintDivisor = emergencyMintDivisor_;
	}

	function setMinBalanceForSwapAndTransfer(
		uint256 minBalanceForSwapAndTransfer_
	) external onlyOwners {
		minBalanceForSwapAndTransfer = minBalanceForSwapAndTransfer_;
	}

	receive() external payable {} // Must be defined so the contract is able to receive ETH from swaps
}
