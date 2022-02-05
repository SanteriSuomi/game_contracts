const SlimeNFT = artifacts.require("SlimeNFT");

module.exports = function (deployer, network, accounts) {
	deployer.deploy(
		SlimeNFT,
		"https://slimekeeper-web-dev.herokuapp.com/api/nft/data?",
		10,
		[
			[1, 0, 5],
			[1, 0, 5],
		],
		{ from: accounts[0] }
	);
};
