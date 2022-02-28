const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");
const truffleAssert = require("truffle-assertions");

contract("NFT Test Mint", async (accounts) => {
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

	it("Can't Mint When Paused", async () => {
		await token.setIsPaused.sendTransaction(true, { from: accounts[0] });
		await truffleAssert.reverts(
			nft.mint.sendTransaction(accounts[1], 1, {
				from: accounts[1],
			}),
			null,
			"Transaction did not revert"
		);

		await token.setIsPaused.sendTransaction(false, { from: accounts[0] });
	});

	it("Can Mint Max", async () => {
		await nft.mint.sendTransaction(accounts[0], 5, {
			from: accounts[0],
		});
		let tokenCount = await nft.balanceOf(accounts[0]);
		assert.equal(tokenCount, 5);
	});

	it("Can't Mint More Than Max", async () => {
		let failed = false;
		try {
			await nft.mint.sendTransaction(accounts[0], 5, {
				from: accounts[0],
			});
		} catch (error) {
			failed = true;
		}
		assert.equal(failed, true);
	});

	it("NFT Data Created Correctly After Minting", async () => {
		let nftDataAtIndex1 = await nft.getNFTData.call(0);
		assert.equal(nftDataAtIndex1[0], 0);
	});

	it("NFT Total Supply Is Correct After Minting", async () => {
		let totalSupply = await nft.totalSupply();
		assert.equal(totalSupply, 5);
	});

	it("NFT Total Supply Is Correct After Minting Once More From Different Address", async () => {
		await nft.setIsPaused.sendTransaction(false, { from: accounts[0] });
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("5000000000000000000000000000000000000"),
			{
				from: accounts[1],
			}
		);
		await token.transfer.sendTransaction(
			accounts[1],
			web3.utils.toBN("400000000000000000000"),
			{
				from: accounts[0],
			}
		);
		await nft.mint.sendTransaction(accounts[1], 1, {
			from: accounts[1],
		});
		let totalSupply = await nft.totalSupply();
		assert.equal(totalSupply, 6);
	});
});
