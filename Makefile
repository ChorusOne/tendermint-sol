.PHONY: clean-protoc build-protoc proto sol-lint js-lint

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
