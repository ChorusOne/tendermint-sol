// SPDX-License-Identifier: TBD
pragma solidity ^0.8.2;

import {
    LightHeader,
    ValidatorSet,
    ClientState,
    ConsensusState,
    TmHeader
} from "./proto/TendermintLight.sol";
import {
    PROOFS_PROTO_GLOBAL_ENUMS,
    CommitmentProof,
    ProofSpec,
    InnerSpec,
    LeafOp,
    InnerOp
} from "./proto/proofs.sol";
import "./proto/TendermintHelper.sol";
import {GoogleProtobufAny as Any} from "./proto/GoogleProtobufAny.sol";
import "./ibc/IClient.sol";
import "./ibc/IBCHost.sol";
import "./ibc/IBCMsgs.sol";
import "./ibc/IBCIdentifier.sol";
import "./utils/Bytes.sol";
import "./utils/Tendermint.sol";
import "./ics23/ics23.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract TendermintLightClient is IClient {
    using Bytes for bytes;
    using Bytes for bytes32;
    using TendermintHelper for TmHeader.Data;
    using TendermintHelper for ConsensusState.Data;
    using TendermintHelper for ValidatorSet.Data;

    struct ProtoTypes {
        bytes32 clientState;
        bytes32 consensusState;
        bytes32 tmHeader;
    }

    ProtoTypes private _pts;
    ProofSpec.Data private _tmProofSpec = ProofSpec.Data({
        leaf_spec: LeafOp.Data({
            hash: PROOFS_PROTO_GLOBAL_ENUMS.HashOp.SHA256,
            prehash_key: PROOFS_PROTO_GLOBAL_ENUMS.HashOp.NO_HASH,
            prehash_value: PROOFS_PROTO_GLOBAL_ENUMS.HashOp.SHA256,
            length: PROOFS_PROTO_GLOBAL_ENUMS.LengthOp.VAR_PROTO,
            prefix: hex"00"
        }),
        inner_spec: InnerSpec.Data({
            child_order: getTmChildOrder(),
            child_size: 32,
            min_prefix_length: 1,
            max_prefix_length: 1,
            empty_child: abi.encodePacked(),
            hash: PROOFS_PROTO_GLOBAL_ENUMS.HashOp.SHA256
        }),
        min_depth: 0,
        max_depth: 0
    });

    constructor() public {
        _pts = ProtoTypes({
            clientState: keccak256(abi.encodePacked("/tendermint.types.ClientState")),
            consensusState: keccak256(abi.encodePacked("/tendermint.types.ConsensusState")),
            tmHeader: keccak256(abi.encodePacked("/tendermint.types.TmHeader"))
        });
    }

    /**
     * @dev getTimestampAtHeight returns the timestamp of the consensus state at the given height.
     */
    function getTimestampAtHeight(
        IBCHost host,
        string memory clientId,
        uint64 height
    ) public override view returns (uint64, bool) {
        (ConsensusState.Data memory consensusState, bool found) = getConsensusState(host, clientId, height);
        if (!found) {
            return (0, false);
        }
        // TODO: Timestamp is a sum of nanoseconds and seconds, this method requires return type update or not? (solidity doesn't support nanoseconds)
        return (uint64(consensusState.timestamp.Seconds), true);
    }

	/**
	* @dev getLatestHeight returs latest height stored in the given client state
	*/
    function getLatestHeight(
        IBCHost host,
        string memory clientId
    ) public override view returns (uint64, bool) {
        (ClientState.Data memory clientState, bool found) = getClientState(host, clientId);
        if (!found) {
            return (0, false);
        }
        return (uint64(clientState.latest_height), true);
    }

    /**
     * @dev checkHeaderAndUpdateState validates the header
     */
    function checkHeaderAndUpdateState(
        IBCHost host,
        string memory clientId,
        bytes memory clientStateBytes,
        bytes memory headerBytes
    ) public override view returns (bytes memory newClientStateBytes, bytes memory newConsensusStateBytes, uint64 height) {
        TmHeader.Data memory tmHeader;
        ClientState.Data memory clientState;
        ConsensusState.Data memory trustedConsensusState;
        ConsensusState.Data memory prevConsState;
        bool ok;
        bool conflictingHeader;

        (tmHeader, ok) = unmarshalTmHeader(headerBytes);
        require(ok, "LC: light block is invalid");

        // Check if the Client store already has a consensus state for the header's height
        // If the consensus state exists, and it matches the header then we return early
        // since header has already been submitted in a previous UpdateClient.
	    (prevConsState, ok) = getConsensusState(host, clientId, uint64(tmHeader.signed_header.header.height));
	    if (ok) {
            // This header has already been submitted and the necessary state is already stored
            // in client store, thus we can return early without further validation.
            if (prevConsState.isEqual(tmHeader.toConsensusState())) {
				return (clientStateBytes, marshalConsensusState(prevConsState), uint64(tmHeader.signed_header.header.height));
            }
            // A consensus state already exists for this height, but it does not match the provided header.
            // Thus, we must check that this header is valid, and if so we will freeze the client.
            conflictingHeader = true;
	    }

        (trustedConsensusState, ok) = getConsensusState(host, clientId, uint64(tmHeader.trusted_height));
        require(ok, "LC: consensusState not found at trusted height");

        (clientState, ok) = unmarshalClientState(clientStateBytes);
        require(ok, "LC: client state is invalid");

        checkValidity(clientState, trustedConsensusState, tmHeader, Duration.Data({Seconds: SafeCast.toInt64(int256(block.timestamp)), nanos: 0}));

	    // Header is different from existing consensus state and also valid, so freeze the client and return
	    if (conflictingHeader) {
            clientState.frozen_height = tmHeader.signed_header.header.height;
            return (
                marshalClientState(clientState),
                marshalConsensusState(tmHeader.toConsensusState()),
                uint64(tmHeader.signed_header.header.height)
            );
	    }

        // TODO: check consensus state monotonicity

        // update the consensus state from a new header and set processed time metadata
        if (tmHeader.signed_header.header.height > clientState.latest_height) {
            clientState.latest_height = tmHeader.signed_header.header.height;
        }

        return (marshalClientState(clientState), marshalConsensusState(tmHeader.toConsensusState()), uint64(clientState.latest_height));
    }

    // checkValidity checks if the Tendermint header is valid.
    function checkValidity(
        ClientState.Data memory clientState,
        ConsensusState.Data memory trustedConsensusState,
        TmHeader.Data memory tmHeader,
        Duration.Data memory currentTime
    ) private view {
	    // assert header height is newer than consensus state
        require(
            tmHeader.signed_header.header.height > tmHeader.trusted_height,
            "LC: header height consensus state height"
        );

        LightHeader.Data memory lc;
        lc.chain_id = clientState.chain_id;
        lc.height = tmHeader.trusted_height;
        lc.time = trustedConsensusState.timestamp;
        lc.next_validators_hash = trustedConsensusState.next_validators_hash;

        ValidatorSet.Data memory trustedVals = tmHeader.trusted_validators;
        SignedHeader.Data memory trustedHeader;
        trustedHeader.header = lc;

        SignedHeader.Data memory untrustedHeader = tmHeader.signed_header;
        ValidatorSet.Data memory untrustedVals = tmHeader.validator_set;

        bool ok = Tendermint.verify(
			clientState.trusting_period,
			clientState.max_clock_drift,
			clientState.trust_level,
            trustedHeader,
            trustedVals,
            untrustedHeader,
            untrustedVals,
            currentTime
        );

        require(ok, "LC: failed to verify header");
    }

    function verifyConnectionState(
        IBCHost host,
        string memory clientId,
        uint64 height,
        bytes memory prefix,
        bytes memory proof,
        string memory connectionId,
        bytes memory connectionBytes // serialized with pb
    ) public override view returns (bool) {
        ClientState.Data memory clientState;
        ConsensusState.Data memory consensusState;
        bool found;

        (clientState, found) = getClientState(host, clientId);
        if (!found) {
            return false;
        }
        if (!validateArgs(clientState, height, prefix, proof)) {
            return false;
        }
        (consensusState, found) = getConsensusState(host, clientId, height);
        if (!found) {
            return false;
        }
        return verifyMembership(proof, consensusState.merkle_root_hash.toBytes32(), prefix, IBCIdentifier.connectionCommitmentSlot(connectionId), keccak256(connectionBytes));
    }

    function verifyChannelState(
        IBCHost host,
        string memory clientId,
        uint64 height,
        bytes memory prefix,
        bytes memory proof,
        string memory portId,
        string memory channelId,
        bytes memory channelBytes // serialized with pb
    ) public override view returns (bool) {
        ClientState.Data memory clientState;
        ConsensusState.Data memory consensusState;
        bool found;

        (clientState, found) = getClientState(host, clientId);
        if (!found) {
            return false;
        }
        if (!validateArgs(clientState, height, prefix, proof)) {
            return false;
        }
        (consensusState, found) = getConsensusState(host, clientId, height);
        if (!found) {
            return false;
        }
        return verifyMembership(proof, consensusState.merkle_root_hash.toBytes32(), prefix, IBCIdentifier.channelCommitmentSlot(portId, channelId), keccak256(channelBytes));
    }

    function verifyPacketCommitment(
        IBCHost host,
        string memory clientId,
        uint64 height,
        uint64 delayPeriodTime,
        uint64 delayPeriodBlocks,
        bytes memory prefix,
        bytes memory proof,
        string memory portId,
        string memory channelId,
        uint64 sequence,
        bytes32 commitmentBytes
    ) public override returns (bool) {
        ClientState.Data memory clientState;
        ConsensusState.Data memory consensusState;
        bool found;

        (clientState, found) = getClientState(host, clientId);
        if (!found) {
            return false;
        }
        if (!validateArgs(clientState, height, prefix, proof)) {
            return false;
        }
        if (!validateDelayPeriod(host, clientId, height, delayPeriodTime, delayPeriodBlocks)) {
            return false;
        }
        (consensusState, found) = getConsensusState(host, clientId, height);
        if (!found) {
            return false;
        }
        return verifyMembership(proof, consensusState.merkle_root_hash.toBytes32(), prefix, IBCIdentifier.packetCommitmentSlot(portId, channelId, sequence), commitmentBytes);
    }

    function verifyPacketAcknowledgement(
        IBCHost host,
        string memory clientId,
        uint64 height,
        uint64 delayPeriodTime,
        uint64 delayPeriodBlocks,
        bytes memory prefix,
        bytes memory proof,
        string memory portId,
        string memory channelId,
        uint64 sequence,
        bytes memory acknowledgement
    ) public override returns (bool) {
        ClientState.Data memory clientState = mustGetClientState(host, clientId);
        if (!validateArgs(clientState, height, prefix, proof)) {
            return false;
        }
        if (!validateDelayPeriod(host, clientId, height, delayPeriodTime, delayPeriodBlocks)) {
            return false;
        }
        bytes32 stateRoot = mustGetConsensusState(host, clientId, height).merkle_root_hash.toBytes32();
        bytes32 ackCommitmentSlot = IBCIdentifier.packetAcknowledgementCommitmentSlot(portId, channelId, sequence);
        bytes32 ackCommitment = host.makePacketAcknowledgementCommitment(acknowledgement);
        return verifyMembership(proof, stateRoot, prefix, ackCommitmentSlot, ackCommitment);
    }

    function verifyClientState(
        IBCHost host,
        string memory clientId,
        uint64 height,
        bytes memory prefix,
        string memory counterpartyClientIdentifier,
        bytes memory proof,
        bytes memory clientStateBytes
    ) public override view returns (bool) {
        ClientState.Data memory clientState;
        ConsensusState.Data memory consensusState;
        bool found;

        (clientState, found) = getClientState(host, clientId);
        if (!found) {
            return false;
        }
        if (!validateArgs(clientState, height, prefix, proof)) {
            return false;
        }
        (consensusState, found) = getConsensusState(host, clientId, height);
        if (!found) {
            return false;
        }
        return verifyMembership(proof, consensusState.merkle_root_hash.toBytes32(), prefix, IBCIdentifier.clientStateCommitmentSlot(counterpartyClientIdentifier), keccak256(clientStateBytes));
    }

    function verifyClientConsensusState(
        IBCHost host,
        string memory clientId,
        uint64 height,
        string memory counterpartyClientIdentifier,
        uint64 consensusHeight,
        bytes memory prefix,
        bytes memory proof,
        bytes memory consensusStateBytes // serialized with pb
    ) public override view returns (bool) {
        ClientState.Data memory clientState;
        ConsensusState.Data memory consensusState;
        bool found;

        (clientState, found) = getClientState(host, clientId);
        if (!found) {
            return false;
        }
        if (!validateArgs(clientState, height, prefix, proof)) {
            return false;
        }
        (consensusState, found) = getConsensusState(host, clientId, height);
        if (!found) {
            return false;
        }
        return verifyMembership(proof, consensusState.merkle_root_hash.toBytes32(), prefix, IBCIdentifier.consensusStateCommitmentSlot(counterpartyClientIdentifier, consensusHeight), keccak256(consensusStateBytes));
    }

    function validateArgs(ClientState.Data memory cs, uint64 height, bytes memory prefix, bytes memory proof) internal pure returns (bool) {
        if (cs.latest_height < int64(height)) {
            return false;
        } else if (prefix.length == 0) {
            return false;
        } else if (proof.length == 0) {
            return false;
        }
        return true;
    }

    function validateDelayPeriod(IBCHost host, string memory clientId, uint64 height, uint64 delayPeriodTime, uint64 delayPeriodBlocks) private view returns (bool) {
        uint64 currentTime = uint64(block.timestamp * 1000 * 1000 * 1000);
        uint64 validTime = mustGetProcessedTime(host, clientId, height) + delayPeriodTime;
        if (currentTime < validTime) {
            return false;
        }
        uint64 currentHeight = uint64(block.number);
        uint64 validHeight = mustGetProcessedHeight(host, clientId, height) + delayPeriodBlocks;
        if (currentHeight < validHeight) {
            return false;
        }
        return true;
    }

    // NOTE: this is a workaround to avoid the error `Stack too deep` in caller side
    function mustGetClientState(IBCHost host, string memory clientId) internal view returns (ClientState.Data memory) {
        (ClientState.Data memory clientState, bool found) = getClientState(host, clientId);
        require(found, "LC: client state not found");
        return clientState;
    }

    // NOTE: this is a workaround to avoid the error `Stack too deep` in caller side
    function mustGetConsensusState(IBCHost host, string memory clientId, uint64 height) internal view returns (ConsensusState.Data memory) {
        (ConsensusState.Data memory consensusState, bool found) = getConsensusState(host, clientId, height);
        require(found, "LC: consensus state not found");
        return consensusState;
    }

    function mustGetProcessedTime(IBCHost host, string memory clientId, uint64 height) internal view returns (uint64) {
        (uint256 processedTime, bool found) = host.getProcessedTime(clientId, height);
        require(found, "LC: processed time not found");
        return uint64(processedTime) * 1000 * 1000 * 1000;
    }

    function mustGetProcessedHeight(IBCHost host, string memory clientId, uint64 height) internal view returns (uint64) {
        (uint256 processedHeight, bool found) = host.getProcessedHeight(clientId, height);
        require(found, "LC: processed height not found");
        return uint64(processedHeight);
    }

    function getClientState(IBCHost host, string memory clientId) public view returns (ClientState.Data memory clientState, bool found) {
        bytes memory clientStateBytes;
        (clientStateBytes, found) = host.getClientState(clientId);
        if (!found) {
            return (clientState, false);
        }
        return (ClientState.decode(Any.decode(clientStateBytes).value), true);
    }

    function getConsensusState(IBCHost host, string memory clientId, uint64 height) public view returns (ConsensusState.Data memory consensusState, bool found) {
        bytes memory consensusStateBytes;
        (consensusStateBytes, found) = host.getConsensusState(clientId, height);
        if (!found) {
            return (consensusState, false);
        }
        return (ConsensusState.decode(Any.decode(consensusStateBytes).value), true);
    }

    function marshalClientState(ClientState.Data memory clientState) internal pure returns (bytes memory) {
        Any.Data memory anyClientState;
        anyClientState.type_url = "/tendermint.types.ClientState";
        anyClientState.value = ClientState.encode(clientState);
        return Any.encode(anyClientState);
    }

    function marshalConsensusState(ConsensusState.Data memory consensusState) internal pure returns (bytes memory) {
        Any.Data memory anyConsensusState;
        anyConsensusState.type_url = "/tendermint.types.ConsensusState";
        anyConsensusState.value = ConsensusState.encode(consensusState);
        return Any.encode(anyConsensusState);
    }

    function unmarshalClientState(bytes memory bz) internal view returns (ClientState.Data memory clientState, bool ok) {
        Any.Data memory anyClientState = Any.decode(bz);
        if (keccak256(abi.encodePacked(anyClientState.type_url)) != _pts.clientState) {
            return (clientState, false);
        }
        return (ClientState.decode(anyClientState.value), true);
    }

    function unmarshalConsensusState(bytes memory bz) internal view returns (ConsensusState.Data memory consensusState, bool ok) {
        Any.Data memory anyConsensusState = Any.decode(bz);
        if (keccak256(abi.encodePacked(anyConsensusState.type_url)) != _pts.consensusState) {
            return (consensusState, false);
        }
        return (ConsensusState.decode(anyConsensusState.value), true);
    }

    function unmarshalTmHeader(bytes memory bz) internal view returns (TmHeader.Data memory header, bool ok) {
        Any.Data memory anyHeader = Any.decode(bz);
        if (keccak256(abi.encodePacked(anyHeader.type_url)) != _pts.tmHeader) {
            return (header, false);
        }
        return (TmHeader.decode(anyHeader.value), true);
    }

    function getTmChildOrder() internal pure returns (int32[] memory) {
        int32[] memory childOrder = new int32[](2);
        childOrder[0] = 0;
        childOrder[1] = 1;

        return childOrder;
    }

    function verifyMembership(
        bytes memory proof,
        bytes32 root,
        bytes memory prefix,
        bytes32 slot,
        bytes32 expectedValue
    ) internal view returns (bool) {
        CommitmentProof.Data memory commitmentProof = CommitmentProof.decode(proof);

        Ics23.VerifyMembershipError vCode = Ics23.verifyMembership(_tmProofSpec, root.toBytes(), commitmentProof, slot.toBytes(), expectedValue.toBytes());

        return vCode == Ics23.VerifyMembershipError.None;
    }
}
