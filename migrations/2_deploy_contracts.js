const Secp256k1Mock = artifacts.require("Secp256k1Mock");

module.exports = function(deployer) {
  deployer.deploy(Secp256k1Mock);
};
