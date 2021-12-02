.PHONY: clean-protoc build-protoc proto sol-lint js-lint sol-format import-ibc test demo

clean-protoc:
	rm -rf ./solidity-protobuf 2>/dev/null

build-protoc: | clean-protoc
	git clone https://github.com/mkaczanowski/solidity-protobuf

proto:
	./scripts/protobuf_compile.sh

sol-lint:
	solhint 'contracts/{utils,mocks}/**/*.sol'

js-lint:
	eslint test/utlis *.js

sol-format:
	npx prettier --write 'contracts/{utils,mocks}/*.sol' 'contracts/proto/{Encoder.sol,TendermintHelper.sol}'

import-ibc:
	./scripts/import_ibc.sh

config:
	export CONF_TPL="./test/demo/src/consts.rs:./scripts/template/contract.rs.tpl" && truffle exec ./scripts/confgen.js --network=$(NETWORK)

test:
	truffle test --network tests

demo:
	# gas-price: 0.5 gwei = 500000000 wei
	cd test/demo && cargo run  -- --max-headers 3 --celo-gas-price 500000000 --celo-usd-price 5.20

deploy:
	# gas-price: 0.5 gwei = 500000000 wei
	NETWORK=celo ./scripts/deploy_with_stats.sh 500000000 5.20
