const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");
const time = require("@openzeppelin/test-helpers").time;

contract("NFT Test Claim", async (accounts) => {
	// if (process.env.NETWORK !== 5777) return; // If not a local test network..

	let nft;
	let token;

	beforeEach(async () => {
		nft = await NFT.deployed();
		token = await Token.deployed();
	});

	it("NFT Generates Some Rewards", async () => {
		await token.approve.sendTransaction(
			nft.address,
			web3.utils.toBN("1000000000000000000000000000000000000"),
			{
				from: accounts[0],
			}
		);
		await nft.mint.sendTransaction(accounts[0], 1, { from: accounts[0] });
		await time.increase(3600);
		let rewardsAfter = await nft.getReward.call(0);
		assert(
			rewardsAfter > web3.utils.toBN("0"),
			"Reward not greater than 0"
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
		try {
			await nft.claimReward.sendTransaction(0);
		} catch (error) {}
		let balanceAfter = await token.balanceOf(accounts[0]);
		let difference = balanceAfter.sub(balanceBefore);
		console.log((await nft.approxAPR(10)).toString());
		assert(difference.eq(web3.utils.toBN(0)));
	});
});
