#!/bin/sh

# update http://localhost:8545@1599200 with ethereum node host/port + latest block
nohup ganache-cli --fork http://localhost:8545@1599200 -p 7545 -h 0.0.0.0 &
truffle test