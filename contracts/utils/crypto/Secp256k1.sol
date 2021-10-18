// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import "../Bytes.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library Secp256k1 {
    using Bytes for bytes;

    uint private constant _PUBKEY_BYTES_LEN_COMPRESSED   = 33;
    uint8 private constant _PUBKEY_COMPRESSED = 0x2;
    uint8 private constant _PUBKEY_UNCOMPRESSED = 0x4;

    /**
     * @dev verifies the secp256k1 signature against the public key and message
     * Tendermint uses RFC6979 and BIP0062 standard, meaning there is no recovery bit ("v" argument) present in the signature.
     * The "v" argument is required by the ecrecover precompile (https://eips.ethereum.org/EIPS/eip-2098) and it can be either 0 or 1.
     *
     * To leverage the ecrecover precompile this method opportunisticly guess the "v" argument. At worst the precompile is called twice,
     * which still might be cheaper than running the verification in EVM bytecode (as solidity lib)
     *
     * See: tendermint/crypto/secp256k1/secp256k1_nocgo.go (Sign, Verify methods)
     */
    function verify(bytes memory message, bytes memory publicKey, bytes memory signature) internal view returns (bool) {
        address signer = Bytes.toAddress(serializePubkey(publicKey, false));
        bytes32 hash = sha256(message);
        (address recovered, ECDSA.RecoverError error) = tryRecover(hash, signature, 27);
        if (error == ECDSA.RecoverError.NoError && recovered != signer) {
            (recovered, error) = tryRecover(hash, signature, 28);
        }

        return error == ECDSA.RecoverError.NoError && recovered == signer;
    }

    /**
     * @dev returns the address that signed the hash.
     * This function flavor forces the "v" parameter instead of trying to derive it from the signature
     *
     * Source: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol#L56
     */
    function tryRecover(bytes32 hash, bytes memory signature, uint8 v) internal pure returns (address, ECDSA.RecoverError) {
        if (signature.length == 65 || signature.length == 64) {
            bytes32 r;
            bytes32 s;
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
            }

            return ECDSA.tryRecover(hash, v, r, s);
        } else {
            return (address(0), ECDSA.RecoverError.InvalidSignatureLength);
        }
    }

    /**
     * @dev check if public key is compressed (length and format)
     */
    function isCompressed(bytes memory pubkey) internal pure returns (bool) {
        return pubkey.length == _PUBKEY_BYTES_LEN_COMPRESSED && uint8(pubkey[0]) & 0xfe == _PUBKEY_COMPRESSED;
    }

    /**
     * @dev convert compressed PK to serialized-uncompressed format
     */
    function serializePubkey(bytes memory pubkey, bool prefix) internal view returns (bytes memory) {
        require(isCompressed(pubkey), "Secp256k1: PK must be compressed");

        uint8 yBit = uint8(pubkey[0]) & 1 == 1 ? 1 : 0;
        uint256 x = Bytes.toUint256(pubkey, 1);
        uint[2] memory xy = decompress(yBit, x);

        if (prefix) {
            return abi.encodePacked(_PUBKEY_UNCOMPRESSED, abi.encodePacked(xy[0]), abi.encodePacked(xy[1]));
        }

        return abi.encodePacked(abi.encodePacked(xy[0]), abi.encodePacked(xy[1]));
    }

    /**
     * @dev decompress a point 'Px', giving 'Py' for 'P = (Px, Py)'
     * 'yBit' is 1 if 'Qy' is odd, otherwise 0.
     *
     * Source: https://github.com/androlo/standard-contracts/blob/master/contracts/src/crypto/Secp256k1.sol#L82
     */
    function decompress(uint8 yBit, uint x) internal view returns (uint[2] memory point) {
        uint p = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
        uint y2 = addmod(mulmod(x, mulmod(x, x, p), p), 7, p);
        uint y_ = modexp(y2, (p + 1) / 4, p);
        uint cmp = yBit ^ y_ & 1;
        point[0] = x;
        point[1] = (cmp == 0) ? y_ : p - y_;
    }

    /**
     * @dev modular exponentiation via EVM precompile (0x05)
     *
     * Source: https://docs.klaytn.com/smart-contract/precompiled-contracts#address-0x05-bigmodexp-base-exp-mod
     */
    function modexp(uint base, uint exponent, uint modulus) internal view returns (uint result) {
        assembly {
            // free memory pointer
            let memPtr := mload(0x40)

            // length of base, exponent, modulus
            mstore(memPtr, 0x20)
            mstore(add(memPtr, 0x20), 0x20)
            mstore(add(memPtr, 0x40), 0x20)

            // assign base, exponent, modulus
            mstore(add(memPtr, 0x60), base)
            mstore(add(memPtr, 0x80), exponent)
            mstore(add(memPtr, 0xa0), modulus)

            // call the precompiled contract BigModExp (0x05)
            let success := staticcall(gas(), 0x05, memPtr, 0xc0, memPtr, 0x20)
            switch success
            case 0 {
                revert(0x0, 0x0)
            } default {
                result := mload(memPtr)
            }
        }
    }
}
