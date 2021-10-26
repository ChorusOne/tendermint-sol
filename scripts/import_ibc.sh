#!/bin/bash

# NOTE: This scripts imports yui-ibc-solidity (IBC Handlers) to the repo. Why?
# 1. The protobuf files must be compiled with the same compiler
# 2. We are only interested in IBC Handlers (nothing else)
# 3. We use newer solidity compiler (see pragma)
#
# This aims to be temporary and we should work to make the IBC handlers a common library

set -eux

rm -rf ./yui-ibc-solidity
git clone https://github.com/hyperledger-labs/yui-ibc-solidity.git 2>/dev/null
cd yui-ibc-solidity && git checkout dc2538d4ac851a0c5588a2a23d0a0ca1e9f3b039

# STEP 1: copy proto files
mkdir -p ../proto/ibc

cp -r ./proto/channel/Channel.proto ../proto/ibc/
cp -r ./proto/connection/Connection.proto ../proto/ibc/

# remove gogoproto references
for proto_file in \
    ../proto/ibc/Channel.proto \
    ../proto/ibc/Connection.proto \
; do
    sed -i "s/\s\[(gogoproto.*\];/;/g" $proto_file
    sed -i "s/option (gogoproto.*//g" $proto_file
    sed -i "s/import \"gogoproto.*//g" $proto_file
done;

# STEP 2: copy IBC core libraries
mkdir -p ../contracts/ibc

for core_lib_file in \
    IBCChannel.sol \
    IBCClient.sol \
    IBCConnection.sol \
    IBCHandler.sol \
    IBCHost.sol \
    IBCIdentifier.sol \
    IBCModule.sol \
    IBCMsgs.sol \
    IClient.sol \
; do
    cp contracts/core/$core_lib_file ../contracts/ibc/
    sed -i "s/pragma experimental ABIEncoderV2;//g" ../contracts/ibc/$core_lib_file
    sed -i "s/pragma solidity.*/pragma solidity ^0.8.2;/g" ../contracts/ibc/$core_lib_file

    sed -i "s/\.\/types\/Channel.sol/\.\.\/proto\/Channel.sol/g" ../contracts/ibc/$core_lib_file
    sed -i "s/\.\/types\/Connection.sol/\.\.\/proto\/Connection.sol/g" ../contracts/ibc/$core_lib_file

    echo -e "// SPDX-License-Identifier: TBD\n// Source: https://github.com/hyperledger-labs/yui-ibc-solidity\n$(cat ../contracts/ibc/${core_lib_file})" > ../contracts/ibc/$core_lib_file
done;
