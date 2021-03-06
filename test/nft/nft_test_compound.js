const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");

contract("NFT Test Compound", async (accounts) => {
	let nft;
	let token;

	before(async () => {
		nft = await NFT.deployed();
		token = await Token.deployed();
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("5000000000000000000000000000000000000"),
			{
				from: accounts[0],
			}
		);
	});

	it("Can Compound One Level", async () => {
		await nft.mint.sendTransaction(accounts[0], 2, { from: accounts[0] });
		await nft.compound.sendTransaction(
			0,
			web3.utils.toBN("100000000000000000000"),
			{
				from: accounts[0],
			}
		);
		let nftData = await nft.getNFTData.call(0);
		assert.equal(nftData[0], 2);
	});

	it("Can Compound Four More Levels", async () => {
		await nft.compound.sendTransaction(
			0,
			web3.utils.toBN("400000000000000000000"),
			{
				from: accounts[0],
			}
		);
		let nftData = await nft.getNFTData.call(0);
		assert.equal(nftData[0], 6);
	});

	it("Can Compound To Max Level", async () => {
		await nft.compound.sendTransaction(
			0,
			web3.utils.toBN("1000000000000000000000"),
			{
				from: accounts[0],
				gas: "500000",
			}
		);
		let nftData = await nft.getNFTData.call(0);
		assert.equal(nftData[0], 10);
	});

	it("Cannot Compound A Max Level Token", async () => {
		let failed = false;
		try {
			await nft.compound.sendTransaction(
				0,
				web3.utils.toBN("100000000000000000000"),
				{
					from: accounts[0],
				}
			);
		} catch (error) {
			failed = true;
		}
		assert.equal(failed, true);
	});
});
