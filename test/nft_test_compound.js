const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");

contract("NFT Test Compound", async (accounts) => {
	it("Can Compound One Level", async () => {
		const nft = await NFT.deployed();
		const token = await Token.deployed();
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("400000000000000000000"),
			{
				from: accounts[0],
			}
		);
		await nft.mint.sendTransaction(accounts[0], 2, { from: accounts[0] });
		await nft.compound.sendTransaction(0, 100, {
			from: accounts[0],
		});
		let nftData = await nft.nftData.call(0);
		assert.equal(nftData.level, 1);
	});

	it("Can Compound Four More Levels", async () => {
		const nft = await NFT.deployed();
		const token = await Token.deployed();
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("500000000000000000000"),
			{
				from: accounts[0],
			}
		);
		await nft.compound.sendTransaction(0, 400, {
			from: accounts[0],
		});
		let nftData = await nft.nftData.call(0);
		assert.equal(nftData.level, 5);
	});

	it("Can Compound To Max Level", async () => {
		const nft = await NFT.deployed();
		const token = await Token.deployed();
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("1000000000000000000000"),
			{
				from: accounts[0],
			}
		);
		await nft.compound.sendTransaction(0, 1000, {
			from: accounts[0],
		});
		let nftData = await nft.nftData.call(0);
		assert.equal(nftData.level, 10);
	});

	it("Cannot Compound A Max Level Token", async () => {
		const nft = await NFT.deployed();
		let throwsError = false;
		try {
			await nft.compound.sendTransaction(0, 100, {
				from: accounts[0],
			});
		} catch (error) {
			throwsError = true;
		}
		assert.equal(throwsError, true);
	});
});
