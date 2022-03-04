const SlimeToken = artifacts.require("SlimeToken");

module.exports = function (deployer, network, accounts) {
	deployer.deploy(SlimeToken, 1000, { from: accounts[0] });
};
