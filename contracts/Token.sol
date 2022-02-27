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
	event LiquidityAdded(
		address sender,
		uint256 amountETH,
		uint256 amountToken
	);

	uint256 public immutable MAX_TOTAL_FEE = 25; // We can never surpass this total fee

	bool public antiBotEnabled;
	bool private antiBotRanOnce; // We can only run antibot once, when initial liquidity is added
	uint256 public antiBotTaxesEndTime; // Time when antibot taxes end
	uint256 public antiBotBlockEndBlock; // Block when antibot blacklister no longer works
	uint256 private antiBotTaxesTimeInSeconds = 3600;
	uint256 private antiBotBlockTime = 2;

	uint256 private antiBotSellDevelopmentTax = 9;
	uint256 private antiBotSellMarketingTax = 9;
	uint256 private antiBotSellLiquidityTax = 3;
	uint256 private antiBotSellRewardsTax = 4;

	mapping(address => bool) public antiBotBlacklist;

	bool public liquidityTaxEnabled = true;

	uint256 private minBalanceToSwapAndTransfer;
	bool private inSwapAndTransfer;

	uint256 public sellDevelopmentTax = 3;
	uint256 public sellMarketingTax = 3;
	uint256 public sellLiquidityTax = 2;
	uint256 public sellRewardsTax = 4;

	uint256 public buyDevelopmentTax = 2;
	uint256 public buyMarketingTax = 2;
	uint256 public buyLiquidityTax = 1;
	uint256 public buyRewardsTax = 2;

	address payable public developmentAddress;
	address payable public marketingAddress;
	address payable public rewardsAddress;
	address payable public gameAddress;
	address payable public nftAddress;

	uint256 private emergencyMintDivisor = 50;

	mapping(address => bool) public isExcludedFromTax;

	IUniswapV2Router02 private router;
	IUniswapV2Pair private pair;

	constructor(
		address gameAddress_,
		address nftAddress_,
		address rewardsAddress_,
		address marketingAddress_,
		address routerAddress_
	) ERC20("Token", "TKN") {
		setIsPaused(true); // Pause trading at the beginning until liquidity is added
		developmentAddress = payable(msg.sender);
		gameAddress = payable(gameAddress_);
		nftAddress = payable(nftAddress_);
		rewardsAddress = payable(rewardsAddress_);
		marketingAddress = payable(marketingAddress_);
		_mint(developmentAddress, 3333 * 10**decimals()); // For adding liquidity and team tokens
		_mint(rewardsAddress, 6667 * 10**decimals()); // Game + NFT rewards
		minBalanceToSwapAndTransfer = totalSupply() / 1000; // If contract balance is minimum 0.1% of total supply, swap to BNB and transfer fees
		isExcludedFromTax[developmentAddress] = true;
		isExcludedFromTax[gameAddress] = true;
		isExcludedFromTax[nftAddress] = true;
		isExcludedFromTax[marketingAddress] = true;
		isExcludedFromTax[rewardsAddress] = true;
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
		) = antiBotGuard(sender, recipient);
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
			tokenBalance >= minBalanceToSwapAndTransfer &&
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

	function antiBotGuard(address sender, address recipient)
		private
		returns (
			uint256 sellDevelopmentTax_,
			uint256 sellMarketingTax_,
			uint256 sellLiquidityTax_,
			uint256 sellRewardsTax_,
			bool guardActivated
		)
	{
		if (!isOwner(tx.origin)) {
			require(
				!antiBotBlacklist[sender] && !antiBotBlacklist[recipient],
				"Sender or recipient blacklisted"
			);
			if (antiBotEnabled) {
				if (block.number <= antiBotBlockEndBlock) {
					antiBotBlacklist[sender] = true;
					guardActivated = true;
				}
				if (block.timestamp <= antiBotTaxesEndTime) {
					sellDevelopmentTax_ = antiBotSellDevelopmentTax;
					sellMarketingTax_ = antiBotSellMarketingTax;
					sellLiquidityTax_ = antiBotSellLiquidityTax;
					sellRewardsTax_ = antiBotSellRewardsTax;
				} else {
					antiBotEnabled = false;
				}
			}
		}
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
			developmentTax = (amount * sellTaxes[0]) / 100;
			marketingTax = (amount * sellTaxes[1]) / 100;
			liquidityTax = (amount * sellTaxes[2]) / 100;
			rewardsTax = (amount * sellTaxes[3]) / 100;
		} else if (sender == address(pair)) {
			// Buying
			developmentTax = (amount * buyDevelopmentTax) / 100;
			marketingTax = (amount * buyMarketingTax) / 100;
			liquidityTax = (amount * buyLiquidityTax) / 100;
			rewardsTax = (amount * buyRewardsTax) / 100;
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

		(bool devSuccess, ) = developmentAddress.call{
			value: ethForDevelopment
		}("");
		(bool marSuccess, ) = marketingAddress.call{ value: ethForMarketing }(
			""
		);

		require(
			devSuccess && marSuccess,
			"Couldn't send to development or marketing wallet"
		);
	}

	function swapAndLiquify(uint256 amountToken) private {
		uint256 half1Token = amountToken / 2;
		uint256 half2Token = amountToken - half1Token;
		uint256 balanceBeforeSwapETH = address(this).balance;
		uint256 balanceAfterSwapETH = swapTokensToETH(half1Token); // Swap half of the tokens to BNB
		uint256 swapDifferenceETH = balanceAfterSwapETH - balanceBeforeSwapETH;
		addLiquidity(swapDifferenceETH, half2Token); // Add the non-swapped tokens and the swapped BNB to liquidity
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

	function createRouterPair(address routerAddress) private {
		router = IUniswapV2Router02(routerAddress);
		pair = IUniswapV2Pair(
			IUniswapV2Factory(router.factory()).createPair(
				address(this),
				router.WETH()
			)
		);
		isExcludedFromTax[address(router)] = true;
		isExcludedFromTax[address(pair)] = true;
	}

	// This function is only to be used by the rewards contract when the rewards pool no longer has rewards
	function emergencyMintRewards() external onlyInternalContracts {
		uint256 amountToMint = totalSupply() / emergencyMintDivisor; // 2% of the supply
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
		antiBotTaxesEndTime = block.timestamp + antiBotTaxesTimeInSeconds;
		antiBotBlockEndBlock = block.number + antiBotBlockTime;
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

	function removeBlacklistedAddress(address address_) external onlyOwners {
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

	function setEmergencyMintDivisor(uint256 value) external onlyOwners {
		emergencyMintDivisor = value;
	}

	function setRouter(address routerAddress) external onlyOwners {
		createRouterPair(routerAddress);
	}

	receive() external payable {} // Must be defined so the contract is able to receive ETH from swaps
}
