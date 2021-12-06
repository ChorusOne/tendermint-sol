// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import "../utils/crypto/MerkleTree.sol";
import {Validator, ValidatorSet, Fraction} from "../proto/TendermintLight.sol";

contract MerkleTreeMock {
    function merkleRootHash(
        bytes memory validators,
        uint256 start,
        uint256 total
    ) public pure returns (bytes32) {
        ValidatorSet.Data memory vs = ValidatorSet.decode(validators);

        require(vs.validators.length == total, "requested vs provided validator size differ");
        if (total > 0) {
            require(vs.validators[0].pub_key.length > 0, "expected ed25519 public key, got empty array");
        }

        return MerkleTree.merkleRootHash(vs.validators, start, total);
    }
}
