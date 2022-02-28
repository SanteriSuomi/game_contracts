const Game = artifacts.require("Game");
const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");
const Rewards = artifacts.require("Rewards");

module.exports = async function (deployer, network, accounts) {
	process.env.NETWORK = network;

	if (network === "testnet") {
		await testnetMigration(deployer, accounts);
	} else if (network === "local_fork") {
		await localforkMigration(deployer, accounts);
	} else if (network === "mainnet") {
		await mainnetMigration(deployer, accounts);
	}
};

async function testnetMigration(deployer, accounts) {
	// Deploy NFT contract
	await deployer.deploy(NFT, { from: accounts[0] });
}

async function localforkMigration(deployer, accounts) {
	// Deploy NFT contract
	await deployer.deploy(NFT, { from: accounts[0] });
	const nftContract = await NFT.deployed();

	// Deploy game contract itself
	await deployer.deploy(Game, { from: accounts[0] });
	const gameContract = await Game.deployed();

	// Deploy Rewards contract
	await deployer.deploy(Rewards, { from: accounts[0] });
	const rewardsContract = await Rewards.deployed();

	// Deploy ERC20 token contract and feed it game and NFT contracts (to mint tokens for them).
	// Deployer wallet is to be used as development wallet
	await deployer.deploy(
		Token,
		gameContract.address,
		nftContract.address,
		rewardsContract.address,
		accounts[9], // Marketing address
		"0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Router address
		{
			from: accounts[0], // Will be the owner
		}
	);
	const tokenContract = await Token.deployed();

	await rewardsContract.setAddresses.sendTransaction(
		tokenContract.address,
		gameContract.address,
		nftContract.address,
		{
			from: accounts[0],
		}
	);

	// Set game contract NFT & ERC20 token contract addresses
	await gameContract.setAddresses.sendTransaction(
		nftContract.address,
		tokenContract.address,
		{
			from: accounts[0],
		}
	);

	// Finally, set the ERC20 token contract address on the NFT contract
	await nftContract.setAddresses.sendTransaction(
		tokenContract.address,
		rewardsContract.address,
		{
			from: accounts[0],
		}
	);

	// Approve token contract to spend deployer's development tokens
	await tokenContract.approve.sendTransaction(
		tokenContract.address,
		web3.utils.toBN(
			"115792089237316195423570985008687907853269984665640564039457584007913129639935" // Maximum value
		),
		{
			from: accounts[0],
		}
	);
}

async function mainnetMigration(deployer, accounts) {}
