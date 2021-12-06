// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import {TmHeader} from "../proto/TendermintLight.sol";
import {GoogleProtobufAny as Any} from "../proto/GoogleProtobufAny.sol";

contract ProtoMock {

    function unmarshalHeader(bytes memory headerBytes, string memory chainID) public {
        Any.Data memory anyHeader = Any.decode(headerBytes);
        TmHeader.Data memory header = TmHeader.decode(anyHeader.value);

        // simple check to verify decoded header
        require(
            keccak256(abi.encodePacked(chainID)) == keccak256(abi.encodePacked(header.signed_header.header.chain_id)),
            "invalid chain_id"
        );
    }
}
