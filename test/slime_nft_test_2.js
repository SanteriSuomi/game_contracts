const SlimeNFT = artifacts.require("SlimeNFT");

contract("slimenft contract test 2", async (accounts) => {
	it("mint 5 tokens", async () => {
		const instance = await SlimeNFT.deployed();
		await instance.mint.sendTransaction(accounts[0], "5", "KEK", {
			from: accounts[0],
			value: web3.utils.toWei("5", "ether"),
		});
		const totalSupply = await instance.totalSupply.call();
		assert.equal(totalSupply, 5);
	});

	it("wrong amount of ether given", async () => {
		const instance = await SlimeNFT.deployed();
		let correctAssert = false;
		try {
			await instance.mint.sendTransaction(accounts[1], "5", "KEK", {
				from: accounts[1],
				value: web3.utils.toWei("4", "ether"),
			});
		} catch (error) {
			console.log(error.reason);
			if (error.reason == "Ether sent is not correct") {
				correctAssert = true;
			}
		}
		assert.equal(correctAssert, true);
	});

	it("can't mint while paused", async () => {
		const instance = await SlimeNFT.deployed();
		let correctAssert = false;
		try {
			await instance.setPaused.sendTransaction(true, {
				from: accounts[0],
			});
			await instance.mint.sendTransaction(accounts[1], "1", "KEK", {
				from: accounts[1],
				value: web3.utils.toWei("1", "ether"),
			});
		} catch (error) {
			if (error.reason == "Minting is paused") {
				correctAssert = true;
			}
		}
		assert.equal(correctAssert, true);
	});

	it("owner can mint while paused", async () => {
		const instance = await SlimeNFT.deployed();
		await instance.setPaused.sendTransaction(true, {
			from: accounts[0],
		});
		await instance.addOwner.sendTransaction(accounts[1], {
			from: accounts[0],
		});
		await instance.mint.sendTransaction(accounts[1], "1", "KEK", {
			from: accounts[1],
			value: web3.utils.toWei("1", "ether"),
		});
		const totalSupply = await instance.totalSupply.call();
		assert.equal(totalSupply, 6);
	});
});
