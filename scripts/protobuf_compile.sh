#!/usr/bin/env bash

set -eu

SOLPB_DIR=./solidity-protobuf

TMP=$(mktemp -d)

for file in $(find ./proto -name '*.proto')
do
    echo "Generating ${file}"

    FNAME=$(basename $file)

    # remove package (issue with protobuf enum prefix)
    sed "s/package tendermint.*;//g" $file > $TMP/$FNAME

    protoc \
        -I$TMP \
        -I${SOLPB_DIR}/protobuf-solidity/src/protoc/include \
        --plugin=protoc-gen-sol=${SOLPB_DIR}/protobuf-solidity/src/protoc/plugin/gen_sol.py \
        --"sol_out=gen_runtime=ProtoBufRuntime.sol&solc_version=0.8.2:$(pwd)/contracts/proto/" \
        $TMP/$FNAME
done
