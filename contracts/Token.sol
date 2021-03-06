// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./PauseOwners.sol";
import "./abstract/AToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

/// @title Game token contract
/// @notice Functions as a reward token for game and NFT contracts
contract Token is AToken {
	event LiquidityAdded(
		address sender,
		uint256 amountETH,
		uint256 amountToken
	);
	event Blacklisted(address address_, uint256 block, uint256 timestamp);
	event Liquified(uint256 amountETH, uint256 amountToken);
	event TradeActivated(uint256 timestamp);
	event Sell(address sender, address recipient, uint256 amount);
	event Buy(address sender, address recipient, uint256 amount);

	uint256 public immutable MAX_TOTAL_FEE = 2000;

	bool public antiBotEnabled;
	bool private antiBotRanOnce;
	uint256 private antiBotTaxesStartTime;
	uint256 private antiBotTaxesEndTime;
	uint256 private antiBotBlockEndBlock;
	uint256 private antiBotTaxesTimeInSeconds = 600;
	uint256 private antiBotBlockTimeInBlocks = 2;
	uint256 private antiBotMaxTX = 100000000000000000000;

	uint256 public antiBotSellDevelopmentTax = 600;
	uint256 public antiBotSellMarketingTax = 600;
	uint256 public antiBotSellRewardsTax = 500;
	uint256 public antiBotSellLiquidityTax = 300;

	mapping(address => bool) public antiBotBlacklist;

	bool public liquidityTaxEnabled = true;

	uint256 private minBalanceForSwapAndTransfer = 10000000000000000000;
	bool private inSwapAndTransfer;

	uint256 public sellDevelopmentTax = 300;
	uint256 public sellMarketingTax = 300;
	uint256 public sellRewardsTax = 250;
	uint256 public sellLiquidityTax = 150;

	uint256 public buyDevelopmentTax = 150;
	uint256 public buyMarketingTax = 150;
	uint256 public buyRewardsTax = 125;
	uint256 public buyLiquidityTax = 75;

	address public developmentAddress;
	address public marketingAddress;
	address public rewardsAddress;
	address public gameAddress;
	address public nftAddress;
	address public liquidityAddress; // This is where LP tokens from tax will be sent

	mapping(address => bool) public isExcludedFromTax;

	uint256 private emergencyMintAmount = 100000000000000000000;

	IUniswapV2Router02 private router;
	IUniswapV2Pair private pair;

	bool private initialLiquidityAdded;

	constructor(
		address gameAddress_,
		address nftAddress_,
		address rewardsAddress_,
		address marketingAddress_,
		address routerAddress_
	) ERC20("Token", "TKN") {
		setIsPaused(true);
		developmentAddress = msg.sender;
		liquidityAddress = msg.sender;
		marketingAddress = marketingAddress_;
		rewardsAddress = rewardsAddress_;
		gameAddress = gameAddress_;
		nftAddress = nftAddress_;
		_mint(developmentAddress, 3333 * 10**decimals()); // For adding liquidity and team tokens
		_mint(rewardsAddress, 6667 * 10**decimals()); // Game + NFT rewards
		isExcludedFromTax[developmentAddress] = true;
		isExcludedFromTax[marketingAddress] = true;
		isExcludedFromTax[rewardsAddress] = true;
		isExcludedFromTax[gameAddress] = true;
		isExcludedFromTax[nftAddress] = true;
		isExcludedFromTax[liquidityAddress] = true;
		isExcludedFromTax[address(this)] = true;
		createRouterPair(routerAddress_);
	}

	modifier lockSwapAndTransfer() {
		inSwapAndTransfer = true;
		_;
		inSwapAndTransfer = false;
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
			notExcludedFromTax &&
			!inSwapAndTransfer &&
			tokenBalance >= minBalanceForSwapAndTransfer &&
			recipient == address(pair) // Is a sell
		) {
			swapAndTransfer(
				tokenBalance,
				sellDevelopmentTax_,
				sellMarketingTax_,
				sellLiquidityTax_
			);
		}

		if (notExcludedFromTax && !inSwapAndTransfer) {
			uint256[] memory sellTaxes = new uint256[](4); // Need to do this abomination because otherwise solidity compiler screams
			sellTaxes[0] = sellDevelopmentTax_;
			sellTaxes[1] = sellMarketingTax_;
			sellTaxes[2] = sellLiquidityTax_;
			sellTaxes[3] = sellRewardsTax_;
			amount = takeFees(amount, sender, recipient, sellTaxes);
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
		require(
			!antiBotBlacklist[sender] && !antiBotBlacklist[recipient],
			"Sender or recipient blacklisted"
		);

		sellDevelopmentTax_ = sellDevelopmentTax;
		sellMarketingTax_ = sellMarketingTax;
		sellLiquidityTax_ = sellLiquidityTax;
		sellRewardsTax_ = sellRewardsTax;

		if (isOwner(tx.origin)) {
			return (
				sellDevelopmentTax_,
				sellMarketingTax_,
				sellLiquidityTax_,
				sellRewardsTax_,
				false
			);
		}

		if (antiBotEnabled) {
			require(amount <= antiBotMaxTX, "Transaction exceeded max amount");
			uint256 time = block.timestamp;
			if (block.number <= antiBotBlockEndBlock) {
				antiBotBlacklist[sender] = true;
				guardActivated = true;
				emit Blacklisted(sender, block.number, block.timestamp);
			} else if (time <= antiBotTaxesEndTime) {
				(
					sellDevelopmentTax_,
					sellMarketingTax_,
					sellLiquidityTax_,
					sellRewardsTax_
				) = scaleTaxesLinearly(time);
			} else {
				antiBotEnabled = false;
			}
		}
	}

	function scaleTaxesLinearly(uint256 time)
		private
		view
		returns (
			uint256 sellDevelopmentTax_,
			uint256 sellMarketingTax_,
			uint256 sellLiquidityTax_,
			uint256 sellRewardsTax_
		)
	{
		uint256 timePassed = 1 + (time - antiBotTaxesStartTime);
		sellDevelopmentTax_ = scaleValueToRangeAndReverse(
			timePassed,
			1,
			antiBotTaxesTimeInSeconds,
			sellDevelopmentTax,
			antiBotSellDevelopmentTax
		);
		sellMarketingTax_ = scaleValueToRangeAndReverse(
			timePassed,
			1,
			antiBotTaxesTimeInSeconds,
			sellMarketingTax,
			antiBotSellMarketingTax
		);
		sellLiquidityTax_ = scaleValueToRangeAndReverse(
			timePassed,
			1,
			antiBotTaxesTimeInSeconds,
			sellLiquidityTax,
			antiBotSellLiquidityTax
		);
		sellRewardsTax_ = scaleValueToRangeAndReverse(
			timePassed,
			1,
			antiBotTaxesTimeInSeconds,
			sellRewardsTax,
			antiBotSellRewardsTax
		);
	}

	function scaleValueToRangeAndReverse(
		uint256 x, // Value to scale
		uint256 minX, // Minimum value of x
		uint256 maxX, // Maximum value of x
		uint256 a, // Range to scale to start
		uint256 b // Range to scale to end
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
			emit Sell(sender, recipient, amount);
		} else if (sender == address(pair)) {
			// Buying
			developmentTax = (amount * buyDevelopmentTax) / 10000;
			marketingTax = (amount * buyMarketingTax) / 10000;
			liquidityTax = (amount * buyLiquidityTax) / 10000;
			rewardsTax = (amount * buyRewardsTax) / 10000;
			emit Buy(sender, recipient, amount);
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
		uint256 balanceAfterSwapETH = swapTokensToETH(half1Token); // Swap half of the tokens to BNB
		uint256 swapDifferenceETH = balanceAfterSwapETH - balanceBeforeSwapETH;
		addLiquidity(swapDifferenceETH, half2Token, liquidityAddress); // Add the non-swapped tokens and the swapped BNB to liquidity
		emit Liquified(swapDifferenceETH, half2Token);
	}

	function addLiquidity(
		uint256 amountETH,
		uint256 amountToken,
		address lpTokenAddress
	) private {
		_approve(address(this), address(router), amountToken);
		router.addLiquidityETH{ value: amountETH }(
			address(this),
			amountToken,
			0,
			0,
			lpTokenAddress,
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

	/// @notice Mints new tokens but only in case of token reward pool drying out
	function emergencyMint() external override {
		require(msg.sender != address(0), "Not callable by zero address");
		require(msg.sender == rewardsAddress, "Address not authorized");
		_mint(rewardsAddress, emergencyMintAmount);
	}

	/// @notice Add liquidity to the token
	/// @param amountToken Amount of token to add to the LP pool pair
	function addInitialLiquidity(uint256 amountToken)
		external
		payable
		onlyOwners
	{
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
		addLiquidity(msg.value, amountToken, msg.sender);
		initialLiquidityAdded = true;
	}

	/// @notice Activates (unpauses) trading along with antibot features
	function activateTradeWithAntibot() external onlyOwners {
		require(
			initialLiquidityAdded,
			"Whoopsie, did you add initial liquidity yet?"
		);
		require(!antiBotRanOnce, "Antibot has already been ran");
		antiBotEnabled = true;
		antiBotRanOnce = true;
		uint256 time = block.timestamp;
		antiBotTaxesStartTime = time;
		antiBotTaxesEndTime = antiBotTaxesStartTime + antiBotTaxesTimeInSeconds;
		antiBotBlockEndBlock = block.number + antiBotBlockTimeInBlocks;
		setIsPaused(false);
		emit TradeActivated(time);
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
		developmentAddress = developmentAddress_;
		marketingAddress = marketingAddress_;
		rewardsAddress = rewardsAddress_;
		isExcludedFromTax[developmentAddress] = true;
		isExcludedFromTax[marketingAddress] = true;
		isExcludedFromTax[rewardsAddress] = true;
	}

	function setInternalAddresses(address gameAddress_, address nftAddress_)
		external
		onlyOwners
	{
		gameAddress = gameAddress_;
		nftAddress = nftAddress_;
		isExcludedFromTax[gameAddress] = true;
		isExcludedFromTax[nftAddress] = true;
	}

	function setLiquidityAddress(address liquidityAddress_)
		external
		onlyOwners
	{
		liquidityAddress = liquidityAddress_;
	}

	function setRouter(address routerAddress) external onlyOwners {
		createRouterPair(routerAddress);
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

	function setEmergencyMintAmount(uint256 emergencyMintAmount_)
		external
		onlyOwners
	{
		emergencyMintAmount = emergencyMintAmount_;
	}

	function setMinBalanceForSwapAndTransfer(
		uint256 minBalanceForSwapAndTransfer_
	) external onlyOwners {
		minBalanceForSwapAndTransfer = minBalanceForSwapAndTransfer_;
	}

	receive() external payable {} // Must be defined so the contract is able to receive ETH from swaps
}
