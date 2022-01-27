const SlimeNFT = artifacts.require("SlimeNFT");

module.exports = function (deployer, network, accounts) {
	deployer.deploy(SlimeNFT, 1000, {
		from: accounts[0],
	});
};
