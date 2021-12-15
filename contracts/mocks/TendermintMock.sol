// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import "../proto/TendermintHelper.sol";
import "../utils/Bytes.sol";
import {SignedHeader, ValidatorSet} from "../proto/TendermintLight.sol";

contract TendermintMock {
    using Bytes for bytes;

    function signedHeaderHash(bytes memory data) public pure returns (bytes32) {
        SignedHeader.Data memory sh = SignedHeader.decode(data);
        return TendermintHelper.hash(sh);
    }

    function validatorSetHash(bytes memory data) public pure returns (bytes32) {
        ValidatorSet.Data memory vs = ValidatorSet.decode(data);
        return TendermintHelper.hash(vs);
    }

    function totalVotingPower(bytes memory data) public pure returns (int64) {
        ValidatorSet.Data memory vs = ValidatorSet.decode(data);
        return TendermintHelper.getTotalVotingPower(vs);
    }

    function getByAddress(bytes memory data, bytes memory addr) public pure returns (uint256 index, bool found) {
        ValidatorSet.Data memory vs = ValidatorSet.decode(data);
        return TendermintHelper.getByAddress(vs, addr);
    }

    function getAddress(bytes memory data, uint index) public pure returns (bytes20 addr) {
        ValidatorSet.Data memory vs = ValidatorSet.decode(data);
        return vs.validators[index].pub_key.toTmAddress();
    }
}
