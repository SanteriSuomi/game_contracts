const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");

contract("NFT Test Compound", async (accounts) => {
	// if (process.env.NETWORK !== 5777) return; // If not a local test network..

	let nft;
	let token;

	beforeEach(async () => {
		nft = await NFT.deployed();
		token = await Token.deployed();
	});

	it("Can Compound One Level", async () => {
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("450000000000000000000"),
			{
				from: accounts[0],
			}
		);
		await nft.mint.sendTransaction(accounts[0], 2, { from: accounts[0] });
		await nft.compound.sendTransaction(0, 100, {
			from: accounts[0],
		});
		let nftData = await nft.getNFTData.call(0);
		assert.equal(nftData[0], 1);
	});

	it("Can Compound Four More Levels", async () => {
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
		let nftData = await nft.getNFTData.call(0);
		assert.equal(nftData[0], 5);
	});

	it("Can Compound To Max Level", async () => {
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
		let nftData = await nft.getNFTData.call(0);
		assert.equal(nftData[0], 10);
	});

	it("Cannot Compound A Max Level Token", async () => {
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
