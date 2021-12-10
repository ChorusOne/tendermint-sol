// SPDX-License-Identifier: TBD
pragma solidity ^0.8.2;

library Bytes {
    function toBytes32(bytes memory bz) internal pure returns (bytes32 ret) {
        require(bz.length == 32, "Bytes: toBytes32 invalid size");
        assembly {
            ret := mload(add(bz, 32))
        }
    }

    function toBytes(bytes32 data) public pure returns (bytes memory) {
        return abi.encodePacked(data);
    }

    function toUint64(bytes memory _bytes, uint256 _start) internal pure returns (uint64 ret) {
        require(_bytes.length >= _start + 8, "Bytes: toUint64 out of bounds");
        assembly {
            ret := mload(add(add(_bytes, 0x8), _start))
        }
    }

    function toUint256(bytes memory _bytes, uint256 _start) internal pure returns (uint256) {
        require(_bytes.length >= _start + 32, "Bytes: toUint256 out of bounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function toAddress(bytes memory _bytes) internal pure returns (address addr) {
        // convert last 20 bytes of keccak hash (bytes32) to address
        bytes32 hash = keccak256(_bytes);
        assembly {
            mstore(0, hash)
            addr := mload(0)
        }
    }
}
