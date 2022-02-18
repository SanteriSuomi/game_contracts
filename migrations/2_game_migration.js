const Game = artifacts.require("Game");
const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");

module.exports = async function (deployer, network, accounts) {
	process.env.NETWORK = network;

	// Deploy game contract itself
	await deployer.deploy(Game, { from: accounts[0] });
	const gameContract = await Game.deployed();

	// Deploy NFT contract
	await deployer.deploy(NFT, { from: accounts[0] });
	const nftContract = await NFT.deployed();

	// Deploy ERC20 token contract and feed it game and NFT contracts (to mint tokens for them).
	// Deployer wallet is to be used as development wallet
	await deployer.deploy(Token, gameContract.address, nftContract.address, {
		from: accounts[0],
	});
	const tokenContract = await Token.deployed();

	// Set game contract NFT & ERC20 token contract addresses
	await gameContract.setNftAddress.sendTransaction(nftContract.address, {
		from: accounts[0],
	});
	await gameContract.setTokenAddress.sendTransaction(tokenContract.address, {
		from: accounts[0],
	});

	// Finally, set the ERC20 token contract address on the NFT contract
	await nftContract.setTokenAddress.sendTransaction(tokenContract.address, {
		from: accounts[0],
	});
};
