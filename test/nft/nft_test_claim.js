const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");
const time = require("@openzeppelin/test-helpers").time;

contract("NFT Test Claim", async (accounts) => {
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

	it("NFT Generates Correct Rewards", async () => {
		await nft.mint.sendTransaction(accounts[0], 1, {
			from: accounts[0],
		});
		await time.increase(31536000); // 1 year
		let rewardsAfter = await nft.getRewardAmount.call(0);
		assert(
			rewardsAfter.eq(web3.utils.toBN("500000000000000000000")), // Considering 500% apr, in 1 year should generate 500 tokens for every 100 tokens invested
			"Reward does not equal 500 tokens"
		);
	});

	it("Can Claim Rewards", async () => {
		let balanceBefore = await token.balanceOf(accounts[0]);
		await nft.claimReward.sendTransaction(0);
		let balanceAfter = await token.balanceOf(accounts[0]);
		assert(
			balanceAfter > balanceBefore,
			"Balance after is not more than before"
		);
	});

	it("Previous Rewards Claim Was Successful", async () => {
		let balanceBefore = await token.balanceOf(accounts[0]);
		await nft.claimReward.sendTransaction(0, {
			from: accounts[0],
			gas: "5000000",
		});
		let balanceAfter = await token.balanceOf(accounts[0]);
		let difference = balanceAfter.sub(balanceBefore);
		assert(
			difference
				.div(web3.utils.toBN("1000000000000000000")) // Token decimals
				.lt(web3.utils.toBN("1")),
			"Difference is not less than 1"
		);
	});
});
