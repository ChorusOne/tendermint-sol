function deployMocks(deployer) {
	const Secp256k1Mock = artifacts.require("Secp256k1Mock");
	const Ed25519Mock = artifacts.require("Ed25519Mock");
	const MerkleTreeMock = artifacts.require("MerkleTreeMock");
	const TendermintMock = artifacts.require("TendermintMock");
	const ProtoMock = artifacts.require("ProtoMock");

	deployer.deploy(Secp256k1Mock);
	deployer.deploy(Ed25519Mock);
	deployer.deploy(MerkleTreeMock);
	deployer.deploy(TendermintMock);
	deployer.deploy(ProtoMock);
}

function deployLightClient(deployer) {
	// contracts
	const IBCHost = artifacts.require("@hyperledger-labs/yui-ibc-solidity/IBCHost");
	const IBCClient = artifacts.require("@hyperledger-labs/yui-ibc-solidity/IBCClient");
	const IBCConnection = artifacts.require("@hyperledger-labs/yui-ibc-solidity/IBCConnection");
	const IBCChannel = artifacts.require("@hyperledger-labs/yui-ibc-solidity/IBCChannel");
	const IBCHandler = artifacts.require("@hyperledger-labs/yui-ibc-solidity/IBCHandler");
	const IBCMsgs = artifacts.require("@hyperledger-labs/yui-ibc-solidity/IBCMsgs");
	const IBCIdentifier = artifacts.require("@hyperledger-labs/yui-ibc-solidity/IBCIdentifier");
	const TendermintLightClient = artifacts.require("TendermintLightClient");

	// libs
	const Bytes = artifacts.require("Bytes");

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

	// TODO: truffle fails to deploy the library automatically,
	// explicit link solves the issue, but still not sure why this is
    // needed... it seems that Bytes is deployed as separate contract?
	deployer.deploy(Bytes);
	deployer.link(Bytes, TendermintLightClient);
	deployer.deploy(TendermintLightClient);

	deployer.deploy(IBCHost).then(function() {
	  return deployer.deploy(IBCHandler, IBCHost.address);
	});
}

module.exports = function(deployer, network) {
  if (network == 'tests') {
	  deployMocks(deployer);
  }

  return deployLightClient(deployer);
};
