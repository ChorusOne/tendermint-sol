.PHONY: proto
proto:
	./scripts/protobuf_compile.sh

.PHONY: sol-lint
sol-lint:
	solhint 'contracts/{utils,mocks}/**/*.sol'

.PHONY: js-lint
js-lint:
	eslint test/utlis *.js

.PHONY: sol-format
sol-format:
	npx prettier --write 'contracts/{utils,mocks}/*.sol' 'contracts/proto/{Encoder.sol,TendermintHelper.sol}'

.PHONY: import-ics23
import-ics23:
	./scripts/import_ics23.sh

.PHONY: config
config:
	export CONF_TPL="./test/demo/src/consts.rs:./scripts/template/contract.rs.tpl" && truffle exec ./scripts/confgen.js --network=$(NETWORK)

.PHONY: test
test:
	npx --no-install truffle test --network tests

.PHONY: demo
demo:
	# gas-price: 0.5 gwei = 500000000 wei
	cd test/demo && cargo run  -- --max-headers 3 --celo-gas-price 500000000 --celo-usd-price 5.20

.PHONY: deploy
deploy:
	# gas-price: 0.5 gwei = 500000000 wei
	./scripts/deploy_with_stats.sh 500000000 5.20
