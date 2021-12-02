// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import { Validator } from "./TendermintLight.sol";
import "./ProtoBufRuntime.sol";

library Encoder {
    uint64 private constant _MAX_UINT64 = 0xFFFFFFFFFFFFFFFF;

    function cdcEncode(string memory item) internal pure returns (bytes memory) {
        uint256 estimatedSize = 1 + ProtoBufRuntime._sz_lendelim(bytes(item).length);
        bytes memory bs = new bytes(estimatedSize);

        uint256 offset = 32;
        uint256 pointer = 32;

        if (bytes(item).length > 0) {
            pointer += ProtoBufRuntime._encode_key(1, ProtoBufRuntime.WireType.LengthDelim, pointer, bs);
            pointer += ProtoBufRuntime._encode_string(item, pointer, bs);
        }

        uint256 sz = pointer - offset;
        assembly {
            mstore(bs, sz)
        }
        return bs;
    }
    function cdcEncode(bytes memory item) internal pure returns (bytes memory) {
        return cdcEncode(1, item);
    }

    function cdcEncode(uint256 key_index, bytes memory item) internal pure returns (bytes memory) {
        uint256 estimatedSize = 1 + ProtoBufRuntime._sz_lendelim(item.length);
        bytes memory bs = new bytes(estimatedSize);

        uint256 offset = 32;
        uint256 pointer = 32;

        if (item.length > 0) {
            pointer += ProtoBufRuntime._encode_key(key_index, ProtoBufRuntime.WireType.LengthDelim, pointer, bs);
            pointer += ProtoBufRuntime._encode_bytes(item, pointer, bs);
        }

        uint256 sz = pointer - offset;
        assembly {
            mstore(bs, sz)
        }
        return bs;
    }

    function cdcEncode(int64 item) internal pure returns (bytes memory) {
        return cdcEncode(1, item);
    }

    function cdcEncode(uint256 key_index, int64 item) internal pure returns (bytes memory) {


        uint256 estimatedSize = 1 + ProtoBufRuntime._sz_int64(item);
        bytes memory bs = new bytes(estimatedSize);

        uint256 offset = 32;
        uint256 pointer = 32;

        if (item != 0) {
            pointer += ProtoBufRuntime._encode_key(key_index, ProtoBufRuntime.WireType.Varint, pointer, bs);
            pointer += ProtoBufRuntime._encode_int64(item, pointer, bs);
        }

        uint256 sz = pointer - offset;
        assembly {
            mstore(bs, sz)
        }
        return bs;
    }

    // TODO: Can we make this cheaper?
    // https://docs.soliditylang.org/en/v0.6.5/types.html#allocating-memory-arrays
    function encodeDelim(bytes memory input) internal pure returns (bytes memory) {
        require(input.length < _MAX_UINT64, "Encoder: out of bounds (uint64)");

        uint64 length = uint64(input.length);
        uint256 additionalEstimated = ProtoBufRuntime._sz_uint64(length);

        bytes memory delimitedPrefix = new bytes(additionalEstimated);
        uint256 delimitedPrefixLen = ProtoBufRuntime._encode_uint64(length, 32, delimitedPrefix);

        assembly {
            mstore(delimitedPrefix, delimitedPrefixLen)
        }

        // concatenate buffers
        return abi.encodePacked(delimitedPrefix, input);
    }





///////////////////////////////////
// Manually serialize SimpleValidator / Validator (with .pub_key as sig)

  function _estimatePK(
    Validator.Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_lendelim(r.pub_key.length);
    return e;
  }


  function _encodePK(Validator.Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    
    if (r.pub_key.length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_bytes(r.pub_key, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nestedPK(Validator.Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    //
    // First encoded `r` into a temporary array, and encode the actual size used.
    // Then copy the temporary array into `bs`.
    //
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimatePK(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encodePK(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }





  function _estimateNew(
    Validator.Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_lendelim(_estimatePK(r));
    e += 1 + ProtoBufRuntime._sz_int64(r.voting_power);
    return e;
  }

  function encodeNew(Validator.Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimateNew(r));
    uint256 sz = _encodeNew(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encodeNew(Validator.Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    
    
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += _encode_nestedPK(r, pointer, bs);
    
    if (r.voting_power != 0) {
    pointer += ProtoBufRuntime._encode_key(
      2,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_int64(r.voting_power, pointer, bs);
    }
    return pointer - offset;
  }

/////////////////////////////////////////////////
}
