const SlimeNFT = artifacts.require("SlimeNFT");

module.exports = function (deployer, network, accounts) {
	deployer.deploy(
		SlimeNFT,
		"KEK",
		10,
		[
			[1, 5],
			[2, 5],
		],
		{ from: accounts[0] }
	);
};
