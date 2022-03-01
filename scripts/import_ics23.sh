#!/bin/bash

# NOTE: This script imports ics23 repo (ICS-23 Proofs) to the repo. Why?
# 1. The protobuf files must be compiled with the same compiler
# 2. The ICS23 branch is still under development
#
# This aims to be a temporary solution

set -eux

rm -rf ./ics23
git clone https://github.com/ChorusOne/ics23.git
cd ics23 && git checkout 2ce6204405b60de138e21a0ca9848921e1bd4d1c

# STEP 1: copy proto files
mkdir -p ../proto/ics23

cp -r ./proofs.proto ../proto/ics23/

# remove package (sol compiler prefixes the struct names with it)
sed -i "s/package .*//g" ../proto/ics23/proofs.proto

# STEP 2: copy IBC core libraries
mkdir -p ../contracts/ics23

for core_lib_file in \
    ics23.sol \
    ics23Compress.sol \
    ics23Ops.sol \
    ics23Proof.sol \
; do
    cp sol/contracts/$core_lib_file ../contracts/ics23/
    sed -i "s/pragma experimental ABIEncoderV2;//g" ../contracts/ics23/$core_lib_file
    sed -i "s/pragma solidity.*/pragma solidity ^0.8.9;/g" ../contracts/ics23/$core_lib_file

    sed -i "s/bytes.concat(/abi.encodePacked(/g" ../contracts/ics23/$core_lib_file
    sed -i "s/\.\/proofs\.sol/\.\.\/proto\/proofs.sol/g" ../contracts/ics23/$core_lib_file
    sed -i "s/OpenZeppelin\/openzeppelin-contracts@4.2.0/@openzeppelin/g" ../contracts/ics23/$core_lib_file
    sed -i "s/GNSPS\/solidity-bytes-utils@0.8.0/solidity-bytes-utils/g" ../contracts/ics23/$core_lib_file
    sed -i "s#\.\/ProtoBufRuntime.sol#@hyperledger-labs/yui-ibc-solidity/contracts/core/types/ProtoBufRuntime.sol#g" ../contracts/ics23/$core_lib_file

    echo -e "// Source: https://github.com/ChorusOne/ics23/tree/giulio/solidity\n$(cat ../contracts/ics23/${core_lib_file})" > ../contracts/ics23/$core_lib_file
done;
