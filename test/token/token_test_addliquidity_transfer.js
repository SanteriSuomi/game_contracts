const Token = artifacts.require("Token");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const fs = require("fs");
const path = require("path");
const time = require("@openzeppelin/test-helpers").time;
const truffleAssert = require("truffle-assertions");

contract("Token Test Add Liquidity And Transfer", async (accounts) => {
	let token;
	let pairAbi;
	let wethAddress;
	let factory;

	before(async () => {
		token = await Token.deployed();

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

		const router = new web3.eth.Contract(
			routerAbi,
			"0x7a250d5630b4cf539739df2c5dacb4c659f2488d"
		);
		wethAddress = await router.methods.WETH().call();

		const factoryAddress = await router.methods
			.factory()
			.call({ from: accounts[0] });
		factory = new web3.eth.Contract(factoryAbi, factoryAddress);
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
		await token.addLiquidity.sendTransaction(10, {
			from: accounts[0],
			value: "10000000000000000000",
		}); // Attempt to add 10 tokens and 10 ether to liquidity

		const pairAddress = await factory.methods
			.getPair(token.address, wethAddress)
			.call({ from: accounts[0] });
		const pair = new web3.eth.Contract(pairAbi, pairAddress);
		const reserves = await pair.methods
			.getReserves()
			.call({ from: accounts[0] });

		const reserve0 = web3.utils.toBN(reserves.reserve0);
		const reserve1 = web3.utils.toBN(reserves.reserve1);
		const zero = web3.utils.toBN("0");
		assert.equal(
			reserve0.gt(zero) && reserve1.gt(zero) && reserve0.eq(reserve1),
			true,
			"Reserves are not equal or either of the reserves are zero"
		);
	});

	it("Antibot Enabled", async () => {
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

	it("Antibot Disabled After Two Blocks", async () => {
		console.log((await token.balanceOf.call(accounts[0])).toString());
		await token.transfer.sendTransaction(accounts[5], 100, {
			from: accounts[0],
		}); // Transfer some balance to account 5 from deployer for testing
		console.log((await token.balanceOf.call(accounts[5])).toString());
		for (let i = 0; i < 2; i++) {
			await time.advanceBlock(); // Advance 2 blocks
		}
		await token.transfer.sendTransaction(accounts[6], 100, {
			from: accounts[5],
		});
		let account3Balance = token.balanceOf.call(accounts[6]);
		let hundredTokens = web3.utils.toBN("100000000000000000000");
		assert.equal(
			account3Balance.eq(hundredTokens),
			true,
			"Transfer should not go through (balance before and after are the same) and address blacklisted"
		);
	});
});
