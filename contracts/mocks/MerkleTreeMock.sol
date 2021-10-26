// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import "../utils/crypto/MerkleTree.sol";
import { Validator, ValidatorSet, Fraction } from "../proto/TendermintLight.sol";

contract MerkleTreeMock {

    function merkleRootHash(bytes memory validators, uint start, uint total) public pure returns (bytes32) {
        ValidatorSet.Data memory vs = ValidatorSet.decode(validators);
        return MerkleTree.merkleRootHash(vs.validators, start, total);
    }
}
