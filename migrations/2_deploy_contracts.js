function deployMocks(deployer) {
	const Secp256k1Mock = artifacts.require("Secp256k1Mock");
	const Ed25519Mock = artifacts.require("Ed25519Mock");
	const MerkleTreeMock = artifacts.require("MerkleTreeMock");
	const TendermintMock = artifacts.require("TendermintMock");

    deployer.deploy(Secp256k1Mock);
    deployer.deploy(Ed25519Mock);
    deployer.deploy(MerkleTreeMock);
    deployer.deploy(TendermintMock);
}

function deployLightClient(deployer) {
	const IBCHost = artifacts.require("IBCHost");
	const IBCClient = artifacts.require("IBCClient");
	const IBCConnection = artifacts.require("IBCConnection");
	const IBCChannel = artifacts.require("IBCChannel");
	const IBCHandler = artifacts.require("IBCHandler");
	const IBCMsgs = artifacts.require("IBCMsgs");
	const IBCIdentifier = artifacts.require("IBCIdentifier");
	const TendermintLightClient = artifacts.require("TendermintLightClient");

	deployer.deploy(IBCIdentifier).then(function() {
	  return deployer.link(IBCIdentifier, [IBCHost, TendermintLightClient, IBCHandler]);
	});
	deployer.deploy(IBCMsgs).then(function() {
	  return deployer.link(IBCMsgs, [IBCClient, IBCConnection, IBCChannel, IBCHandler, TendermintLightClient]);
	});
	deployer.deploy(IBCClient).then(function() {
	  return deployer.link(IBCClient, [IBCHandler, IBCConnection, IBCChannel]);
	});
	deployer.deploy(IBCConnection).then(function() {
	  return deployer.link(IBCConnection, [IBCHandler, IBCChannel]);
	});
	deployer.deploy(IBCChannel).then(function() {
	  return deployer.link(IBCChannel, [IBCHandler]);
	});
	deployer.deploy(TendermintLightClient);
	deployer.deploy(IBCHost).then(function() {
	  return deployer.deploy(IBCHandler, IBCHost.address);
	});
}

module.exports = function(deployer, network) {
  if (network == 'tests') {
      return deployMocks(deployer);
  }

  return deployLightClient(deployer);
};
