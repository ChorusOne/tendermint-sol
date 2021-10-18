const Secp256k1Mock = artifacts.require("Secp256k1Mock");
const Ed25519Mock = artifacts.require("Ed25519Mock");

module.exports = function(deployer) {
  deployer.deploy(Secp256k1Mock);
  deployer.deploy(Ed25519Mock);
};
