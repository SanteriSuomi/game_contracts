const SlimeNFT = artifacts.require("SlimeNFT");

contract("slimenft contract test 1", async (accounts) => {
	it("maxmint valid after instantiation", async () => {
		const instance = await SlimeNFT.deployed();
		const maxMint = await instance.maxMint.call();
		assert.equal(maxMint, 10);
	});

	it("currentprice valid after instantiation", async () => {
		const instance = await SlimeNFT.deployed();
		const currentPrice = await instance.getCurrentPriceRange.call();
		assert.equal(currentPrice[0], 1);
	});

	it("exceeds max mint amount", async () => {
		const instance = await SlimeNFT.deployed();
		let correctAssert = false;
		try {
			await instance.mint.sendTransaction(accounts[0], "11", "KEK", [], {
				from: accounts[0],
				value: web3.utils.toWei("11", "ether"),
			});
		} catch (error) {
			if (error.reason == "Max mint amount reached") {
				correctAssert = true;
			}
		}
		assert.equal(correctAssert, true);
	});

	it("reach supply cap", async () => {
		const instance = await SlimeNFT.deployed();
		let correctAssert = false;
		try {
			await instance.mint.sendTransaction(accounts[0], "5", "KEK", [], {
				from: accounts[0],
				value: web3.utils.toWei("5", "ether"),
			});
			await instance.mint.sendTransaction(accounts[1], "5", "KEK", [], {
				from: accounts[1],
				value: web3.utils.toWei("5", "ether"),
			});
			await instance.mint.sendTransaction(accounts[2], "5", "KEK", [], {
				from: accounts[2],
				value: web3.utils.toWei("5", "ether"),
			});
		} catch (error) {
			if (error.reason == "Supply cap reached") {
				correctAssert = true;
			}
		}
		assert.equal(correctAssert, true);
	});
});
