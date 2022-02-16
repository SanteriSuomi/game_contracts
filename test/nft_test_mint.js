const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");

contract("NFT Test 1", async (accounts) => {
	it("Can Mint Max", async () => {
		const nft = await NFT.deployed();
		const token = await Token.deployed();
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("500000000000000000000"),
			{
				from: accounts[0],
			}
		);
		await nft.mint.sendTransaction(accounts[0], 5, { from: accounts[0] });
		let tokenCount = await nft.balanceOf(accounts[0]);
		assert.equal(tokenCount, 5);
	});

	it("Can't Mint More Than Max", async () => {
		const nft = await NFT.deployed();
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
		const nft = await NFT.deployed();
		let nftDataAtIndex1 = await nft.nftData.call(0);
		assert.equal(nftDataAtIndex1.level, 1);
	});

	it("NFT Total Supply Is Correct After Minting", async () => {
		const nft = await NFT.deployed();
		let totalSupply = await nft.totalSupply();
		assert.equal(totalSupply, 5);
	});

	it("NFT Total Supply Is Correct After Minting Once More From Different Address", async () => {
		const nft = await NFT.deployed();
		const token = await Token.deployed();
		await token.transfer.sendTransaction(
			accounts[1],
			web3.utils.toBN("400000000000000000000"),
			{
				from: accounts[0],
			}
		);
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("500000000000000000000"),
			{
				from: accounts[1],
			}
		);
		await nft.mint.sendTransaction(accounts[1], 1, { from: accounts[1] });
		let totalSupply = await nft.totalSupply();
		assert.equal(totalSupply, 6);
	});
});
