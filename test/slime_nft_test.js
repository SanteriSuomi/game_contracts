const SlimeNFT = artifacts.require("SlimeNFT");

contract("slimeft contract", async (accounts) => {
	it("max should be 1000", async () => {
		const instance = await SlimeNFT.deployed();
		const max = await instance.maximumSupply.call();
		assert.equal(max, 1000);
	});

	it("current should be 0", async () => {
		const instance = await SlimeNFT.deployed();
		const current = await instance.totalSupply.call();
		assert.equal(current, 0);
	});

	it("can't mint while canMint is false", async () => {
		const instance = await SlimeNFT.deployed();
		let success = true;
		try {
			await instance.mint.call(accounts[0]);
		} catch (error) {
			success = false;
		}
		assert.equal(success, false);
	});

	it("can mint once canMint set to true", async () => {
		const instance = await SlimeNFT.deployed();
		await instance.setMintEnabled(true, { from: accounts[0] });
		let success = true;
		try {
			await instance.mint(accounts[0], "king/main.png", {
				from: accounts[0],
			});
		} catch (error) {
			success = false;
		}
		console.log(await instance.tokenURI(0));
		assert.equal(success, true);
	});

	it("non-owner can't access setCanMint", async () => {
		const instance = await SlimeNFT.deployed();
		let success = true;
		try {
			await instance.setMintEnabled(true, { from: accounts[1] });
		} catch (error) {
			success = false;
		}
		assert.equal(success, false);
	});
});
