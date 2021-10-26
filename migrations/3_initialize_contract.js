const IBCHost = artifacts.require("IBCHost");
const IBCHandler = artifacts.require("IBCHandler");
const TendermintLightClient = artifacts.require("TendermintLightClient");

const TendermintLightClientType = "07-tendermint"

module.exports = async function (deployer) {
  const ibcHost = await IBCHost.deployed();
  const ibcHandler = await IBCHandler.deployed();

  for(const f of [
    () => ibcHost.setIBCModule(IBCHandler.address),
    () => ibcHandler.registerClient(TendermintLightClientType, TendermintLightClient.address),
  ]) {
    const result = await f();
    if(!result.receipt.status) {
      console.log(result);
      throw new Error(`transaction failed to execute. ${result.tx}`);
    }
  }
};
