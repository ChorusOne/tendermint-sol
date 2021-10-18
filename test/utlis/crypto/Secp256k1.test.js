const Secp256k1Mock = artifacts.require("Secp256k1Mock");
const truffleAssert = require('truffle-assertions');


contract('Secp256k1Mock', () => {

  it('serializes compressed public key', async () => {
    const mock = await Secp256k1Mock.deployed();
    
    const cases = [
        {
            pk: '0x02fc6c77e870eb482c4d7a0126cf528c3a6775f7fe3f291cbcd1dc0c3b7cc213ae',
            expected: '0x04fc6c77e870eb482c4d7a0126cf528c3a6775f7fe3f291cbcd1dc0c3b7cc213ae107a10e61e384f16a3ef1273b55d354b4681774567e9499f21b7eb5f51eb528a'
        },
        {
            pk: '0x0317088765d17a1232f9757ef7cf992046f383468de5e0e434379de1b8299039ff',
            expected: '0x0417088765d17a1232f9757ef7cf992046f383468de5e0e434379de1b8299039ffcf73f4c9a35d4deb22114bdf5f3b6a6b7f5c985f5c21ef3dd68b722f9dd1ed43'
        },
        {
            pk: '0x0317088765', // too short
            expected: ''
        },
        {
            pk: '0x0517088765d17a1232f9757ef7cf992046f383468de5e0e434379de1b8299039ff', // wrong prefix
            expected: ''
        },
    ];

    for (let c of cases) {
        const serialized = mock.serializePubkey.call(c.pk, true);

        if (c.expected.length) {
            assert.equal(await serialized, c.expected, "invalid serialized public key");
        } else {
            await truffleAssert.reverts(serialized, "Secp256k1: PK must be compressed");
        }
    }
  });

  it('verifies secp256k1 signature', async () => {

    const mock = await Secp256k1Mock.deployed();

    const cases = [
        {
            msg: '0x6c080211140000000000000022480a201b234e2eb7fbd0045d30aff27f378f33bde4a93d7dff48e047e23dd64ea6551d122408011220ec9447ed497eeb1cdbe0121a8c7a449b84ac5d4b8618bb984b3e8206028d4f732a0b08d0f6ad8b0610daa4b3173208776f726d686f6c65',
            sig: '0x051412327c5e160d767ef8b081c0e72f329130400b42553f4aa06a4d19397e395371ecd46c59eadc13a92e78fe420bf20bf55d608334981eb13a79ea266d9e28',
            v: 28
        },
        {
            msg: '0x6c080211080000000000000022480a20d892db02a8f682a8ecff369537f7f47672c1b73ae1dbfe234ebace17bfc0c3f412240801122098bf0b3e24565f0ccd182715619192f8df3ad2d447a62f5274bcaa8f3057731d2a0b08a2f2ad8b0610caabcd7c3208776f726d686f6c65',
            sig: '0xb149b87d189c08f0ca164a5c0e4a28e6acfd0b745767a673905742ba9682a4a00d346b7a0a8b92f0d779b053c042a3ed0c7b5ca5a1e0b608e1aedeea395841d5',
            v: 27
        }
    ];

    // positive case
    for (let c of cases) {
        const pk = '0x0317088765d17a1232f9757ef7cf992046f383468de5e0e434379de1b8299039ff';
        const verify = await mock.verify.call(c.msg, pk, c.sig);
        const recovered = await mock.recover.call(c.msg, c.sig, c.v);

        assert.equal(recovered, '0x083C31D442e15874407c8d9d17D17f26bf53ef34', "recovered invalid signer address");
        assert.equal(verify, true, "secp256k1 signature verification failed");
    }

    // negative case
    for (let c of cases) {
        const pk = '0x0317088765d17a1232f9757ef7cf992046f383468de5e0e434379de1b8299039fe';
        const verify = await mock.verify.call(c.msg, pk, c.sig);
        const recovered = await mock.recover.call(c.msg, c.sig, c.v == 27 ? 28 : 27);

        assert.notEqual(recovered, '0x083C31D442e15874407c8d9d17D17f26bf53ef34', "recovered address worked?");
        assert.equal(verify, false, "secp256k1 verification should fail for wrong pk");
    }
  });
});
