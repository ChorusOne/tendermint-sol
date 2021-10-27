// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

library Ed25519 {

    uint private constant _CELO_ED25519_PRECOMPILE_ADDR   = 0xf3;

    /**
     * @dev verifies the ed25519 signature against the public key and message
     * This method works only with Celo Blockchain, by calling the ed25519 precompile (currently unavailable in vanilla EVM)
     *
     * See: tendermint/crypto/secp256k1/secp256k1_nocgo.go (Sign, Verify methods)
     */
    function verify(bytes memory message, bytes memory publicKey, bytes memory signature) internal view returns (bool) {
        require(signature.length == 64, "Ed25519: siganture length != 64");
        require(publicKey.length == 32, "Ed25519: pubkey length != 32");

        bytes memory all = abi.encodePacked(publicKey, signature, message);
        bytes32 result = 0x0000000000000000000000000000000000000000000000000000000000000001;

        assembly {
            let success := staticcall(gas(), _CELO_ED25519_PRECOMPILE_ADDR, add(all, 0x20), mload(all), result, 0x20)

            switch success
            case 0 {
                revert(0, "ed25519 precompile failed")
            } default {
                result := mload(result)
            }
        }

        // result > 0 is an error
        return (bytes32(0x0000000000000000000000000000000000000000000000000000000000000000) == result);
    }
}
