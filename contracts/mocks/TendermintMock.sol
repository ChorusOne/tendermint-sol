// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import "../utils/Tendermint.sol";
import { SignedHeader } from "../proto/TendermintLight.sol";

contract TendermintMock {

    function signedHeaderHash(bytes memory data) public pure returns (bytes32) {
        SignedHeader.Data memory sh = SignedHeader.decode(data);
        return Tendermint.hash(sh);
    }
}
