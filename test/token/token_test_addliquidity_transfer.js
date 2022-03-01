const Token = artifacts.require("Token");
const Rewards = artifacts.require("Rewards");
const fs = require("fs");
const path = require("path");
const time = require("@openzeppelin/test-helpers").time;
const truffleAssert = require("truffle-assertions");

contract("Token Test Add Liquidity And Transfer", async (accounts) => {
	let token;
	let rewards;
	let router;
	let pairAbi;
	let wethAddress;
	let factory;
	let pair;

	before(async () => {
		token = await Token.deployed();
		rewards = await Rewards.deployed();

		const routerAbi = JSON.parse(
			fs.readFileSync(
				path.resolve(__dirname, "../../abi/router_abi.json")
			)
		);
		const factoryAbi = JSON.parse(
			fs.readFileSync(
				path.resolve(__dirname, "../../abi/factory_abi.json")
			)
		);
		pairAbi = JSON.parse(
			fs.readFileSync(path.resolve(__dirname, "../../abi/pair_abi.json"))
		);

		router = new web3.eth.Contract(
			routerAbi,
			"0x7a250d5630b4cf539739df2c5dacb4c659f2488d"
		);
		wethAddress = await router.methods.WETH().call();

		const factoryAddress = await router.methods
			.factory()
			.call({ from: accounts[0] });
		factory = new web3.eth.Contract(factoryAbi, factoryAddress);

		const pairAddress = await factory.methods
			.getPair(token.address, wethAddress)
			.call({ from: accounts[0] });
		pair = new web3.eth.Contract(pairAbi, pairAddress);
	});

	it("Can't Transfer As Trading Paused", async () => {
		// First transfer some account other than the deployer as can trade even when paused
		await token.transfer.sendTransaction(accounts[1], 100, {
			from: accounts[0],
		});

		await truffleAssert.reverts(
			token.transfer.sendTransaction(accounts[2], 100, {
				from: accounts[1],
			}),
			null,
			"Transaction did not revert"
		);
	});

	it("Can Add Liquidity", async () => {
		await token.addInitialLiquidity.sendTransaction(
			web3.utils.toBN("2000000000000000000000"),
			{
				from: accounts[0],
				value: "10000000000000000000",
			}
		); // Attempt to add 2000 tokens and 10 ether to liquidity

		let reserves = await pair.methods
			.getReserves()
			.call({ from: accounts[0] });

		const reserve0 = web3.utils.toBN(reserves.reserve0);
		const reserve1 = web3.utils.toBN(reserves.reserve1);
		const zero = web3.utils.toBN(0);
		assert.equal(
			reserve0.gt(zero) && reserve1.gt(zero) && reserve0.gt(reserve1),
			true
		);
	});

	it("Antibot Enabled", async () => {
		await token.transfer.sendTransaction(accounts[1], 100, {
			from: accounts[0],
		});
		await token.activateTradeWithAntibot.sendTransaction({
			from: accounts[0],
		}); // Activate antibot and unpause trade
		let balanceBefore = await token.balanceOf.call(accounts[1]);
		await token.transfer.sendTransaction(accounts[2], 100, {
			from: accounts[1],
		});
		let balanceAfter = await token.balanceOf.call(accounts[1]);
		let isBlacklisted = await token.antiBotBlacklist.call(accounts[1]);
		assert.equal(
			balanceBefore.eq(balanceAfter) && isBlacklisted,
			true,
			"Transfer should not go through (balance before and after are the same) and address blacklisted"
		);
	});

	it("Antibot Blacklist Disabled After Two Blocks", async () => {
		let hundredTokens = web3.utils.toBN("100000000000000000000"); // Hundred tokens converted to token decimals
		await token.transfer.sendTransaction(accounts[5], hundredTokens, {
			from: accounts[0],
		}); // Transfer some balance to account 5 from deployer for testing
		for (let i = 0; i < 2; i++) {
			await time.advanceBlock(); // Advance 3 blocks
		}
		await token.transfer.sendTransaction(accounts[6], hundredTokens, {
			from: accounts[5],
			gas: "5000000",
		});
		let balance = await token.balanceOf.call(accounts[6]);
		assert.equal(
			balance.eq(hundredTokens),
			true,
			"Transfer should not go through (balance before and after are the same) and address blacklisted"
		);
	});

	it("Can Buy Through Router", async () => {
		let buyAmount = web3.utils.toBN("1000000000000000000"); // 1 ether
		let deadline = (await time.latest()) + 120; // Two minutes
		let tokenPath = [wethAddress, token.address];
		let balanceBefore = await token.balanceOf.call(accounts[0]);
		await router.methods
			.swapExactETHForTokens(0, tokenPath, accounts[0], deadline)
			.send({
				value: buyAmount,
				from: accounts[0],
				gas: "5000000",
			});
		let balanceAfter = await token.balanceOf.call(accounts[0]);
		let difference = balanceAfter - balanceBefore;
		assert(
			web3.utils
				.toBN(difference)
				.gt(web3.utils.toBN("180322180000000000000")),
			"Balance after swap should be more than 180 tokens"
		);
	});

	it("Taxes Are Correct When Selling And Antibot Is Activated", async () => {
		await testTaxes(7, "25000000000000000000");
	});

	it("Taxes Are Correct When Selling And Antibot Is Deactivated", async () => {
		await time.increase(4000);
		await testTaxes(8, "12000000000000000000");
	});

	async function testTaxes(accountNumber, mustEqualTax) {
		let sellAmount = web3.utils.toBN("100000000000000000000"); // Hundred tokens converted to token decimals
		await token.transfer.sendTransaction(
			accounts[accountNumber],
			web3.utils.toBN("100000000000000000000"),
			{
				from: accounts[0],
			}
		); // Transfer some balance to account 5 from deployer for testing
		await token.approve.sendTransaction(
			router.options.address,
			sellAmount,
			{
				from: accounts[accountNumber],
			}
		);
		let deadline = (await time.latest()) + 120; // Two minutes
		let tokenPath = [token.address, wethAddress];
		let rewardsAddressBalanceBefore = await token.balanceOf.call(
			rewards.address
		);
		await router.methods
			.swapExactTokensForETHSupportingFeeOnTransferTokens(
				sellAmount,
				0, // Any amount
				tokenPath,
				accounts[accountNumber],
				deadline
			)
			.send({
				from: accounts[accountNumber],
				gas: "5000000",
			});
		let tokenAddressBalance = await token.balanceOf.call(token.address);
		let rewardsAddressBalanceAfter = await token.balanceOf.call(
			rewards.address
		);
		let rewardsAddressBalanceDifference = rewardsAddressBalanceAfter.sub(
			rewardsAddressBalanceBefore
		);
		let mustEqualTaxBN = web3.utils.toBN(mustEqualTax);
		let added = tokenAddressBalance.add(rewardsAddressBalanceDifference);
		let decimalSub = web3.utils.toBN("10000000000000000000");
		assert.equal(
			added.gt(mustEqualTaxBN.sub(decimalSub)) &&
				added.lt(mustEqualTaxBN.add(decimalSub)),
			true
		);
	}
});
