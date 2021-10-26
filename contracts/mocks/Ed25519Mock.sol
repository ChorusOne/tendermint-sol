// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import "../utils/crypto/Ed25519.sol";

contract Ed25519Mock {

    function verify(bytes memory message, bytes memory publicKey, bytes memory sig) public view returns (bool) {
        return Ed25519.verify(message, publicKey, sig);
    }
}
