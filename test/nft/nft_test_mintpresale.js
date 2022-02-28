const NFT = artifacts.require("NFT");
const truffleAssert = require("truffle-assertions");

contract("NFT Test Mint Presale", async (accounts) => {
	let nft;
	let presalePrice;

	before(async () => {
		nft = await NFT.deployed();
		presalePrice = await nft.presalePrice();
	});

	it("Can Mint One", async () => {
		await nft.setPresalePaused.sendTransaction(false, {
			from: accounts[0],
		});
		await nft.mintPresale.sendTransaction(accounts[1], 1, {
			from: accounts[1],
			value: presalePrice,
		});
		let tokenCount = await nft.balanceOf(accounts[1]);
		assert.equal(tokenCount, 1);
	});

	it("Can Mint Max Per Address", async () => {
		await nft.mintPresale.sendTransaction(accounts[1], 4, {
			from: accounts[1],
			value: presalePrice * 4,
		});
		let tokenCount = await nft.balanceOf(accounts[1]);
		assert.equal(tokenCount, 5);
	});

	it("Can't Mint Above Limit", async () => {
		await truffleAssert.reverts(
			nft.mintPresale.sendTransaction(accounts[1], 1, {
				from: accounts[1],
				value: presalePrice,
			}),
			null,
			"Transaction doesn't revert"
		);
	});

	it("Can Mint Once More From Another Address", async () => {
		await nft.mintPresale.sendTransaction(accounts[2], 4, {
			from: accounts[2],
			value: presalePrice * 4,
		});
		let tokenCount = await nft.balanceOf(accounts[2]);
		assert.equal(tokenCount, 4);
	});

	it("Total Supply Is Correct", async () => {
		let totalSupply = await nft.totalSupply();
		assert.equal(totalSupply, 9);
	});

	it("Can Withdraw Presale Ether", async () => {
		await nft.addOwner.sendTransaction(accounts[9], {
			from: accounts[0],
		});
		await nft.setPresaleEnded.sendTransaction(true, {
			from: accounts[0],
		});
		let balanceBefore = web3.utils.toBN(
			await web3.eth.getBalance(accounts[9])
		);
		await nft.claimPresaleETH.sendTransaction({
			from: accounts[9],
		});
		let balanceAfter = web3.utils.toBN(
			await web3.eth.getBalance(accounts[9])
		);
		assert.equal(balanceAfter.gt(balanceBefore), true);
	});
});
