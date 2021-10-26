// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import "../utils/crypto/Secp256k1.sol";

contract Secp256k1Mock {
    function serializePubkey(bytes memory pubkey, bool prefix) public view returns (bytes memory) {
        return Secp256k1.serializePubkey(pubkey, prefix);
    }

    function verify(
        bytes memory message,
        bytes memory publicKey,
        bytes memory sig
    ) public view returns (bool) {
        return Secp256k1.verify(message, publicKey, sig);
    }

    function recover(
        bytes memory message,
        bytes memory sig,
        uint8 v
    ) public pure returns (address) {
        (address recovered, ) = Secp256k1.tryRecover(sha256(message), sig, v);
        return recovered;
    }
}
