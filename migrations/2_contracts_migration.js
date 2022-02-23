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

	let routerAddress;
	if (network == "testnet") {
		// BSC testnet
		routerAddress = "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3";
	} else {
		// Ethereum mainnet (forked locally)
		routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
	}

	try {
		await tokenContract.setRouter.sendTransaction(routerAddress, {
			from: accounts[0],
		});
	} catch (error) {} // Setting router on a local non-forked network fails (as it doesn't exist), which is fine

	// Set correct tax addresses
	await tokenContract.setTaxAddresses.sendTransaction(
		accounts[0],
		accounts[1],
		accounts[2],
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
};
