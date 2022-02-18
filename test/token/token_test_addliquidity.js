const Token = artifacts.require("Token");
const time = require("@openzeppelin/test-helpers").time;

contract("NFT Test Claim", async (accounts) => {
	let token;

	beforeEach(async () => {
		token = await Token.deployed();
	});

	it("Can Add Initial Liquidity", async () => {
		// token.addLiquidity.sendTransaction(100, { from: accounts[0] });
	});
});
