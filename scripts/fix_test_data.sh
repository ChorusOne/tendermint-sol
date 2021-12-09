#!/bin/bash

for f in $(ls test/data/header.*.validator_set.json); do
    cat $f | jq -r '.validators=[(.validators[] | (.pub_key=.pub_key.sum))]' | sed  's/Ed25519/ed25519/g' > /tmp/tmp.jq && mv /tmp/tmp.jq $f
done
