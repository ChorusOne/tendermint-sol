#!/bin/bash

set -eu

GAS_PRICE=$1  # wei
CELO_TO_USD=$2

truffle deploy --describe-json --network $NETWORK --reset | tee deploy.log

echo "====== STATS ====="

cat deploy.log  | grep -oP "MIGRATION_STATUS:\K.*" | jq "select(.status == \"deployed\") | {\"\(.data.contract.contractName)\": {address: .data.contract.address, gasUsed: .data.receipt.gasUsed, gasPrice: $GAS_PRICE, fee_celo: (($GAS_PRICE * .data.receipt.gasUsed) / 1000000000000000000), fee_usd: ((($GAS_PRICE * .data.receipt.gasUsed) / 1000000000000000000) * $CELO_TO_USD)}}" | jq -n '[inputs] | add' 
