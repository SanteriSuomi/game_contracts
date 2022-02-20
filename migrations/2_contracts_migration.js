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

	let routerAddress =
		network === "testnet"
			? "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3" // Testnet
			: "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // Mainnet
	await tokenContract.setRouter.sendTransaction(routerAddress, {
		from: accounts[0],
	});

	await tokenContract.approve.sendTransaction(
		tokenContract.address,
		web3.utils.toBN(
			"115792089237316195423570985008687907853269984665640564039457584007913129639935"
		),
		{
			from: accounts[0],
		}
	);

	await tokenContract.approve.sendTransaction(
		"0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3",
		web3.utils.toBN(
			"115792089237316195423570985008687907853269984665640564039457584007913129639935"
		),
		{
			from: accounts[0],
		}
	);

	await tokenContract.setTaxAddresses.sendTransaction(
		accounts[0],
		accounts[1],
		accounts[2],
		{
			from: accounts[0],
		}
	);
};
