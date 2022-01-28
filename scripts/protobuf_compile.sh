#!/usr/bin/env bash

set -eu

if [ -z "$SOLPB_DIR" ]; then
    echo "variable SOLPB_DIR must be set"
    exit 1
fi

TMP=$(mktemp -d)

for file in $(find ./proto -name '*.proto')
do
    echo "Generating ${file}"

    FNAME=$(basename $file)

    # remove package (issue with protobuf enum prefix)
    sed "s/package tendermint.*;//g" $file > $TMP/$FNAME

    protoc \
        -I$TMP \
	-I'./node_modules/@hyperledger-labs/yui-ibc-solidity/proto' \
	-I'./node_modules/@hyperledger-labs/yui-ibc-solidity/third_party/proto' \
        -I${SOLPB_DIR}/protobuf-solidity/src/protoc/include \
	--plugin=protoc-gen-sol=${SOLPB_DIR}/protobuf-solidity/src/protoc/plugin/gen_sol.py \
	--sol_out="use_runtime=@hyperledger-labs/yui-ibc-solidity/contracts/core/types/ProtoBufRuntime.sol&solc_version=0.8.9&allow_reserved_keywords=on:$(pwd)/contracts/proto" \
        $TMP/$FNAME
done
