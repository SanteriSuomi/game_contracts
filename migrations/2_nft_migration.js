const SlimeNFT = artifacts.require("SlimeNFT");

module.exports = function (deployer, network, accounts) {
	deployer.deploy(
		SlimeNFT,
		1000,
		"https://slimekeeper-nft-data.s3.eu-north-1.amazonaws.com/nft/",
		{
			from: accounts[0],
		}
	);
};
