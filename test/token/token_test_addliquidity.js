const Token = artifacts.require("Token");
const fs = require("fs");
const path = require("path");

contract("Token Test Add Liquidity", async (accounts) => {
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

	it("Can Add Liquidity", async () => {
		await token.addLiquidity.sendTransaction(10, {
			from: accounts[0],
			value: "10000000000000000000",
			gas: "500000",
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
		assert(reserve0.eq(reserve1), "Reserves are not equal");
	});
});
