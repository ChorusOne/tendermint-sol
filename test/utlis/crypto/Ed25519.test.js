const Ed25519Mock = artifacts.require('Ed25519Mock')
const truffleAssert = require('truffle-assertions')

contract('Ed25519Mock', () => {
  it('verifies ed25519 signature', async () => {
    // currently ed25519 verification uses CeloEVM precompile, skip if not
    // running on CeloEVM
    const nodeInfo = await web3.eth.getNodeInfo()
    if (!nodeInfo.startsWith('celo')) {
      console.warn('ed25519 signature verification SKIPPED')
      return
    }

    const mock = await Ed25519Mock.deployed()

    const cases = [
      {
        msg: '0x6c080211ae0000000000000022480a201be10f1d98a078e24f7d153d435287f6c62dbbd84a1347e8d1779e6b90d9adc0122408011220be2920b8b9906102d29a0367c69e03d5f0082c49686f5c737fe02bd54ac69c842a0b0890dcb58b0610a883e33b3208776f726d686f6c65',
        sig: '0x22aa68771d6c00e322e6341e948f728bfe900423d2faed6f71a3c2e03af256524e213a9eef75f80e50406464d18b1e65c7b95819597123cab5ea8f6f2da8ba08',
        expected: true
      },
      {
        msg: '0x6c080211ae0000000000000022480a201be10f1d98a078e24f7d153d435287f6c62dbbd84a1347e8d1779e6b90d9adc0122408011220be2920b8b9906102d29a0367c69e03d5f0082c49686f5c737fe02bd54ac69c842a0b0890dcb58b0610a883e33b3208776f726d686f6c65',
        // invalid sig
        sig: '0x22aa68771d6c00e322e6341e948f728bfe900423d2faed6f71a3c2e03af256524e213a9eef75f80e50406464d18b1e65c7b95819597123cab5ea8f6f2da8ba09',
        expected: false
      }
    ]

    // positive case
    for (const c of cases) {
      const pk = '0x1361bf11753516e1c96d0ec78c59ba44964b4b28bbfe50242b6eced65420f9c8'
      const verify = await mock.verify.call(c.msg, pk, c.sig)

      assert.equal(verify, c.expected, 'ed25519 signature verification failed')
    }
  })
})
