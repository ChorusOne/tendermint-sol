.PHONY: clean-protoc build-protoc proto

clean-protoc:
	rm -rf ./solidity-protobuf 2>/dev/null

build-protoc: | clean-protoc
	git clone https://github.com/mkaczanowski/solidity-protobuf

proto:
	./scripts/protobuf_compile.sh
