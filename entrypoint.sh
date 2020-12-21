#!/bin/sh

# update http://localhost:8545@1599200 with ethereum node host/port + latest block
nohup ganache-cli --fork https://mainnet.infura.io/v3/c6a4304e987b45eb969975a39d076a83@11499350 -p 7545 -h 0.0.0.0 &
truffle test