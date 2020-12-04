var path = require('path');
require('truffle-flattener-wrapper')(path.resolve(__dirname, '.'), path.resolve(__dirname, 'out')).catch(console.error);