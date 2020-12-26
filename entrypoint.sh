#!/bin/sh

# update http://localhost:8545@1599200 with ethereum node host/port + latest block
nohup ganache-cli --fork $ALCHEMY_URL -p 7545 -h 0.0.0.0 &
truffle migrate
truffle test