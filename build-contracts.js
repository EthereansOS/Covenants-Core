var path = require('path');
require('truffle-flattener-wrapper')(path.resolve(__dirname, 'contracts'), path.resolve(__dirname, 'flat')).catch(console.error);