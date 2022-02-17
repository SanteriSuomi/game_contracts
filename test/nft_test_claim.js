const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");
const time = require("@openzeppelin/test-helpers").time;

contract("NFT Test Compound", async (accounts) => {
	it("NFT Generates Some Rewards", async () => {
		const nft = await NFT.deployed();
		const token = await Token.deployed();
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("1000000000000000000000000000000000000"),
			{
				from: accounts[0],
			}
		);
		await nft.mint.sendTransaction(accounts[0], 1, { from: accounts[0] });
		let rewardsBefore = await nft.reward.call(0);
		await time.increase(300);
		let rewardsAfter = await nft.reward.call(0);
		console.log("Rewards before " + rewardsBefore.toString());
		console.log("Rewards after " + rewardsAfter.toString());
		assert(rewardsAfter > web3.utils.toBN("0"));
	});
});
