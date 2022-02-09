const Game = artifacts.require("Game");
const NFT = artifacts.require("NFT");
const Token = artifacts.require("Token");

module.exports = async function (deployer, network, accounts) {
	await deployer.deploy(Game, { from: accounts[0] });
	const gameContract = await Game.deployed();

	await deployer.deploy(NFT, { from: accounts[0] });
	const nftContract = await NFT.deployed();

	await deployer.deploy(Token, gameContract.address, nftContract.address, {
		from: accounts[0],
	});
	const tokenContract = await Token.deployed();
	console.log(
		(await tokenContract.balanceOf.call(gameContract.address)).toString()
	);
};
