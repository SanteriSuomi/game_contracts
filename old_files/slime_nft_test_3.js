const SlimeNFT = artifacts.require("SlimeNFT");
const SlimeToken = artifacts.require("SlimeToken");

contract("slimenft contract test 3", async (accounts) => {
	it("compounding function sends 100 tokens to nft contract", async () => {
		const nft = await SlimeNFT.deployed();
		const token = await SlimeToken.deployed();
		await nft.setToken.sendTransaction(token.address);
		await token.setNFT.sendTransaction(nft.address);
		await token.approve.sendTransaction(nft.address, 1000, {
			from: accounts[0],
		});
		await nft.mint.sendTransaction(accounts[0], 1, "KEK", [], {
			from: accounts[0],
			value: web3.utils.toWei("1", "ether"),
		});
		await nft.compound.sendTransaction(100, 1, {
			from: accounts[0],
		});
		assert.equal(await token.balanceOf(nft.address), 100);
	});

	it("compounding should set nft level to 5", async () => {
		const nft = await SlimeNFT.deployed();
		await nft.compound.sendTransaction(150, 1, {
			from: accounts[0],
		});
		assert.equal((await nft.slimeInfo.call(1)).level, 5);
	});

	it("compounding beyond max level should return excess tokens", async () => {
		const nft = await SlimeNFT.deployed();
		const token = await SlimeToken.deployed();
		await nft.compound.sendTransaction(300, 1, {
			from: accounts[0],
		});
		assert.equal(await token.balanceOf(accounts[0]), 500);
	});

	it("token uri should be correct", async () => {
		const nft = await SlimeNFT.deployed();
		const uri = await nft.tokenURI.call(1);
		console.log(uri);
		assert.equal(
			uri,
			"https://slimekeeper-web-dev.herokuapp.com/api/nft/data?level=10&locked=500"
		);
	});
});
