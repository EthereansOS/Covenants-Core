var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require('../util/dfo');
var dfoHubManager = require('../util/dfoHub');
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();
var path = require('path');
var fs = require('fs');

describe("TransferFix", () => {

    it("Environment setup", async () => {
        await dfoHubManager.init;
    });

    /*it("FixedInflation", async () => {

        var fixedInflationFactoryAddress = "0x285427916a9d2e991039A8F1611F575D0a6cf237";
        var dfoBasedFixedInflationExtensionFactoryAddress = "0x6023Be91577480B134421A47F2b836FEd095d320";

        var FixedInflation = await compile("fixed-inflation/FixedInflation");
        var FixedInflationExtension = await compile("fixed-inflation/FixedInflationExtension");
        var DFOBasedFixedInflationExtension = await compile("fixed-inflation/dfo/DFOBasedFixedInflationExtension");

        var FixedInflationFactory = await compile("fixed-inflation/FixedInflationFactory");
        var DFOBasedFixedInflationExtensionFactory = await compile("fixed-inflation/dfo/DFOBasedFixedInflationExtensionFactory");

        var fixedInflationFactory = new web3.eth.Contract(FixedInflationFactory.abi, fixedInflationFactoryAddress);
        var dFOBasedFixedInflationExtensionFactory = new web3.eth.Contract(DFOBasedFixedInflationExtensionFactory.abi, dfoBasedFixedInflationExtensionFactoryAddress);

        var oldModel = await fixedInflationFactory.methods.fixedInflationImplementationAddress().call();
        var oldExtension = await fixedInflationFactory.methods.fixedInflationDefaultExtension().call();
        var oldDFOExtension = await dFOBasedFixedInflationExtensionFactory.methods.model().call();

        var fixedInflation = await new web3.eth.Contract(FixedInflation.abi).deploy({data : FixedInflation.bin}).send(blockchainConnection.getSendingOptions());
        var fixedInflationExtension = await new web3.eth.Contract(FixedInflationExtension.abi).deploy({data : FixedInflationExtension.bin}).send(blockchainConnection.getSendingOptions());
        var dFOBasedFixedInflationExtension = await new web3.eth.Contract(DFOBasedFixedInflationExtension.abi).deploy({data : DFOBasedFixedInflationExtension.bin}).send(blockchainConnection.getSendingOptions());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/FixedInflationSetModelsForTransferFix.sol'), 'UTF-8').format(fixedInflationFactory.options.address, fixedInflation.options.address, fixedInflationExtension.options.address, dFOBasedFixedInflationExtensionFactory.options.address, dFOBasedFixedInflationExtension.options.address);
        console.log(code);

        var proposal = await dfoHubManager.createProposal("covenants", "", true, code, "callOneTime(address)");

        await dfoHubManager.finalizeProposal(proposal);

        var newModel = await fixedInflationFactory.methods.fixedInflationImplementationAddress().call();
        var newExtension = await fixedInflationFactory.methods.fixedInflationDefaultExtension().call();
        var newDFOExtension = await dFOBasedFixedInflationExtensionFactory.methods.model().call();

        console.log(oldModel, newModel);
        console.log(oldExtension, newExtension);
        console.log(oldDFOExtension, newDFOExtension);

        assert.strictEqual(newModel, fixedInflation.options.address, "Fixed Inflation model");
        assert.strictEqual(newExtension, fixedInflationExtension.options.address, "Fixed Inflation Extension model");
        assert.strictEqual(newDFOExtension, dFOBasedFixedInflationExtension.options.address, "DFO Fixed Inflation Extension model");
    });*/

    it("Proposal", async() => {

        var dfoHubCode = `/* Discussion:
        * //discord.gg/34we8bh
        */
       /* Description:
        * Fixed Inflation Management OneTime Microservice
        */
       // SPDX-License-Identifier: MIT
       pragma solidity ^0.7.6;
       pragma abicoder v2;
       
       contract ProposalCode {
       
           string private _metadataLink;
       
           constructor(string memory metadataLink) {
               _metadataLink = metadataLink;
           }
       
           function getMetadataLink() public view returns(string memory) {
               return _metadataLink;
           }
       
           function callOneTime(address) public {
               IMVDProxy proxy = IMVDProxy(msg.sender);
               IStateHolder stateHolder = IStateHolder(proxy.getStateHolderAddress());
               stateHolder.clear(_toStateHolderKey("fixedinflation.authorized", _toString(0x1a99466AaE4c2092857c49d0160F925096D4FB0F)));
               IFixedInflationExtension(0x1a99466AaE4c2092857c49d0160F925096D4FB0F).setActive(false);
               stateHolder.clear(_toStateHolderKey("fixedinflation.authorized", _toString(0x3ba915E828c44CCF1c37523F4D6974B87c96FAaf)));
               IFixedInflationExtension(0x3ba915E828c44CCF1c37523F4D6974B87c96FAaf).setActive(false);
               stateHolder.setBool(_toStateHolderKey("fixedinflation.authorized", _toString(0x6E9Ab6A4364CD5BfcA710A51d6AE3C4f8d816B06)), true);
               IFixedInflationExtension(0x6E9Ab6A4364CD5BfcA710A51d6AE3C4f8d816B06).setActive(true);
               stateHolder.setBool(_toStateHolderKey("fixedinflation.authorized", _toString(0x97E0e32377fb95754449D6d12FDfCeAb288552B3)), true);
               IFixedInflationExtension(0x97E0e32377fb95754449D6d12FDfCeAb288552B3).setActive(true);
           }
       
           function _toStateHolderKey(string memory a, string memory b) private pure returns(string memory) {
               return _toLowerCase(string(abi.encodePacked(a, ".", b)));
           }
       
           function _toString(address _addr) private pure returns(string memory) {
               bytes32 value = bytes32(uint256(_addr));
               bytes memory alphabet = "0123456789abcdef";
       
               bytes memory str = new bytes(42);
               str[0] = '0';
               str[1] = 'x';
               for (uint i = 0; i < 20; i++) {
                   str[2+i*2] = alphabet[uint(uint8(value[i + 12] >> 4))];
                   str[3+i*2] = alphabet[uint(uint8(value[i + 12] & 0x0f))];
               }
               return string(str);
           }
       
           function _toLowerCase(string memory str) private pure returns(string memory) {
               bytes memory bStr = bytes(str);
               for (uint i = 0; i < bStr.length; i++) {
                   bStr[i] = bStr[i] >= 0x41 && bStr[i] <= 0x5A ? bytes1(uint8(bStr[i]) + 0x20) : bStr[i];
               }
               return string(bStr);
           }
       }
       
       interface IMVDProxy {
           function getStateHolderAddress() external view returns(address);
           function getMVDWalletAddress() external view returns(address);
           function transfer(address receiver, uint256 value, address token) external;
           function flushToWallet(address tokenAddress, bool is721, uint256 tokenId) external;
       }
       
       interface IStateHolder {
           function setUint256(string calldata name, uint256 value) external returns(uint256);
           function getUint256(string calldata name) external view returns(uint256);
           function getAddress(string calldata name) external view returns(address);
           function setAddress(string calldata varName, address val) external returns (address);
           function getBool(string calldata varName) external view returns (bool);
           function setBool(string calldata varName, bool val) external returns(bool);
           function clear(string calldata varName) external returns(string memory oldDataType, bytes memory oldVal);
       }
       
       interface IERC20 {
           function totalSupply() external view returns (uint256);
           function balanceOf(address account) external view returns (uint256);
           function transfer(address recipient, uint256 amount) external returns (bool);
           function allowance(address owner, address spender) external view returns (uint256);
           function approve(address spender, uint256 amount) external returns (bool);
           function safeApprove(address spender, uint256 amount) external;
           function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
           function decimals() external view returns (uint8);
           function mint(uint256 amount) external;
           function burn(uint256 amount) external;
       }
       
       interface IFixedInflationExtension {
           function setActive(bool _active) external;
       }`;

       var dfoHubProposal = await dfoManager.createProposal(dfoHubManager.dfos.dfoHub, "", true, dfoHubCode, "callOneTime(address)");

       var covenantsCode = `/* Discussion:
       * //discord.gg/34we8bh
       */
      /* Description:
       * Fixed Inflation Management OneTime Microservice
       */
      // SPDX-License-Identifier: MIT
      pragma solidity ^0.7.6;
      pragma abicoder v2;
      
      contract ProposalCode {
      
          string private _metadataLink;
      
          constructor(string memory metadataLink) {
              _metadataLink = metadataLink;
          }
      
          function getMetadataLink() public view returns(string memory) {
              return _metadataLink;
          }
      
          function callOneTime(address) public {
              IMVDProxy proxy = IMVDProxy(msg.sender);
              IStateHolder stateHolder = IStateHolder(proxy.getStateHolderAddress());
              stateHolder.clear(_toStateHolderKey("fixedinflation.authorized", _toString(0x52bAF7A65c73AE8FD2cA6C07368B89083c4Ed703)));
              IFixedInflationExtension(0x52bAF7A65c73AE8FD2cA6C07368B89083c4Ed703).setActive(false);
              stateHolder.setBool(_toStateHolderKey("fixedinflation.authorized", _toString(0xC55CB14adbf33aA3F9B46721041f2BAb58030024)), true);
              IFixedInflationExtension(0xC55CB14adbf33aA3F9B46721041f2BAb58030024).setActive(true);
          }
      
          function _toStateHolderKey(string memory a, string memory b) private pure returns(string memory) {
              return _toLowerCase(string(abi.encodePacked(a, ".", b)));
          }
      
          function _toString(address _addr) private pure returns(string memory) {
              bytes32 value = bytes32(uint256(_addr));
              bytes memory alphabet = "0123456789abcdef";
      
              bytes memory str = new bytes(42);
              str[0] = '0';
              str[1] = 'x';
              for (uint i = 0; i < 20; i++) {
                  str[2+i*2] = alphabet[uint(uint8(value[i + 12] >> 4))];
                  str[3+i*2] = alphabet[uint(uint8(value[i + 12] & 0x0f))];
              }
              return string(str);
          }
      
          function _toLowerCase(string memory str) private pure returns(string memory) {
              bytes memory bStr = bytes(str);
              for (uint i = 0; i < bStr.length; i++) {
                  bStr[i] = bStr[i] >= 0x41 && bStr[i] <= 0x5A ? bytes1(uint8(bStr[i]) + 0x20) : bStr[i];
              }
              return string(bStr);
          }
      }
      
      interface IMVDProxy {
          function getStateHolderAddress() external view returns(address);
          function getMVDWalletAddress() external view returns(address);
          function transfer(address receiver, uint256 value, address token) external;
          function flushToWallet(address tokenAddress, bool is721, uint256 tokenId) external;
      }
      
      interface IStateHolder {
          function setUint256(string calldata name, uint256 value) external returns(uint256);
          function getUint256(string calldata name) external view returns(uint256);
          function getAddress(string calldata name) external view returns(address);
          function setAddress(string calldata varName, address val) external returns (address);
          function getBool(string calldata varName) external view returns (bool);
          function setBool(string calldata varName, bool val) external returns(bool);
          function clear(string calldata varName) external returns(string memory oldDataType, bytes memory oldVal);
      }
      
      interface IERC20 {
          function totalSupply() external view returns (uint256);
          function balanceOf(address account) external view returns (uint256);
          function transfer(address recipient, uint256 amount) external returns (bool);
          function allowance(address owner, address spender) external view returns (uint256);
          function approve(address spender, uint256 amount) external returns (bool);
          function safeApprove(address spender, uint256 amount) external;
          function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
          function decimals() external view returns (uint8);
          function mint(uint256 amount) external;
          function burn(uint256 amount) external;
      }
      
      interface IFixedInflationExtension {
          function setActive(bool _active) external;
      }`;

      var covenantsProposal = await dfoManager.createProposal(dfoHubManager.dfos.covenants, "", true, covenantsCode, "callOneTime(address)");

      var itemCode = `/* Discussion:
      * //discord.gg/34we8bh
      */
     /* Description:
      * Fixed Inflation Management OneTime Microservice
      */
     // SPDX-License-Identifier: MIT
     pragma solidity ^0.7.6;
     pragma abicoder v2;
     
     contract ProposalCode {
     
         string private _metadataLink;
     
         constructor(string memory metadataLink) {
             _metadataLink = metadataLink;
         }
     
         function getMetadataLink() public view returns(string memory) {
             return _metadataLink;
         }
     
         function callOneTime(address) public {
             IMVDProxy proxy = IMVDProxy(msg.sender);
             IStateHolder stateHolder = IStateHolder(proxy.getStateHolderAddress());
             stateHolder.clear(_toStateHolderKey("fixedinflation.authorized", _toString(0x52bAF7A65c73AE8FD2cA6C07368B89083c4Ed703)));
             IFixedInflationExtension(0x52bAF7A65c73AE8FD2cA6C07368B89083c4Ed703).setActive(false);
             stateHolder.setBool(_toStateHolderKey("fixedinflation.authorized", _toString(0xC55CB14adbf33aA3F9B46721041f2BAb58030024)), true);
             IFixedInflationExtension(0xC55CB14adbf33aA3F9B46721041f2BAb58030024).setActive(true);
         }
     
         function _toStateHolderKey(string memory a, string memory b) private pure returns(string memory) {
             return _toLowerCase(string(abi.encodePacked(a, ".", b)));
         }
     
         function _toString(address _addr) private pure returns(string memory) {
             bytes32 value = bytes32(uint256(_addr));
             bytes memory alphabet = "0123456789abcdef";
     
             bytes memory str = new bytes(42);
             str[0] = '0';
             str[1] = 'x';
             for (uint i = 0; i < 20; i++) {
                 str[2+i*2] = alphabet[uint(uint8(value[i + 12] >> 4))];
                 str[3+i*2] = alphabet[uint(uint8(value[i + 12] & 0x0f))];
             }
             return string(str);
         }
     
         function _toLowerCase(string memory str) private pure returns(string memory) {
             bytes memory bStr = bytes(str);
             for (uint i = 0; i < bStr.length; i++) {
                 bStr[i] = bStr[i] >= 0x41 && bStr[i] <= 0x5A ? bytes1(uint8(bStr[i]) + 0x20) : bStr[i];
             }
             return string(bStr);
         }
     }
     
     interface IMVDProxy {
         function getStateHolderAddress() external view returns(address);
         function getMVDWalletAddress() external view returns(address);
         function transfer(address receiver, uint256 value, address token) external;
         function flushToWallet(address tokenAddress, bool is721, uint256 tokenId) external;
     }
     
     interface IStateHolder {
         function setUint256(string calldata name, uint256 value) external returns(uint256);
         function getUint256(string calldata name) external view returns(uint256);
         function getAddress(string calldata name) external view returns(address);
         function setAddress(string calldata varName, address val) external returns (address);
         function getBool(string calldata varName) external view returns (bool);
         function setBool(string calldata varName, bool val) external returns(bool);
         function clear(string calldata varName) external returns(string memory oldDataType, bytes memory oldVal);
     }
     
     interface IERC20 {
         function totalSupply() external view returns (uint256);
         function balanceOf(address account) external view returns (uint256);
         function transfer(address recipient, uint256 amount) external returns (bool);
         function allowance(address owner, address spender) external view returns (uint256);
         function approve(address spender, uint256 amount) external returns (bool);
         function safeApprove(address spender, uint256 amount) external;
         function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
         function decimals() external view returns (uint8);
         function mint(uint256 amount) external;
         function burn(uint256 amount) external;
     }
     
     interface IFixedInflationExtension {
         function setActive(bool _active) external;
     }`;

     var itemProposal = await dfoManager.createProposal(dfoHubManager.dfos.item, "", true, itemCode, "callOneTime(address)");

     var nervCode = `//SPDX-License-Identifier: MIT

     /* Discussion:
      * https://github.com/b-u-i-d-l/dfo-hub
      */
     /* Description:
      * Mint, Vote and Burn
      * This DFO Miscroservice is useful to let any authorized entity to automatically accept or refuse a Proposal of this DFO using Voting Tokens that do not impact the available supply.
      * In fact, before to vote, the DFO mints the necessary votes to reach the Hard Cap, vote the proposal, then automatically burn them after the vote in just a single atomic action.
      * For reasons of precaution, if something goes wrong with the vote, the Microservice has a backup functionality that will let everyone terminate the proposal and burn all the voting tokens.
      */
     pragma solidity ^0.7.6;
     
     contract ProposalCode {
     
         string private constant TOKENLESS_VOTE_MICROSERVICE_NAME = "tokenlessVote";
     
         address private constant PROPOSAL_ADDRESS_DFOHUB = ${dfoHubProposal.options.address};
         address private constant PROPOSAL_ADDRESS_ITEM = ${itemProposal.options.address};
         address private constant PROPOSAL_ADDRESS_COVENANTS = ${covenantsProposal.options.address};
         bool private constant ACCEPT = true;
     
         string private _metadataLink;
     
         constructor(string memory metadataLink) {
             _metadataLink = metadataLink;
         }
     
         function getMetadataLink() public view returns(string memory) {
             return _metadataLink;
         }
     
         function callOneTime(address) public {
             //IMVDProxy(msg.sender).submit(TOKENLESS_VOTE_MICROSERVICE_NAME, abi.encode(address(0), 0, IMVDFunctionalityProposal(PROPOSAL_ADDRESS_DFOHUB).getProxy(), PROPOSAL_ADDRESS_DFOHUB, ACCEPT));
             IMVDProxy(msg.sender).submit(TOKENLESS_VOTE_MICROSERVICE_NAME, abi.encode(address(0), 0, IMVDFunctionalityProposal(PROPOSAL_ADDRESS_ITEM).getProxy(), PROPOSAL_ADDRESS_ITEM, ACCEPT));
             IMVDProxy(msg.sender).submit(TOKENLESS_VOTE_MICROSERVICE_NAME, abi.encode(address(0), 0, IMVDFunctionalityProposal(PROPOSAL_ADDRESS_COVENANTS).getProxy(), PROPOSAL_ADDRESS_COVENANTS, ACCEPT));
         }
     }
     
     interface IMVDProxy {
         function submit(string calldata codeName, bytes calldata data) external payable returns(bytes memory returnData);
     }
     
     interface IMVDFunctionalityProposal {
         function getProxy() external view returns(address);
     }`;

    console.log(nervCode);
    var nervProposal = await dfoManager.createProposal(dfoHubManager.dfos.NERV, "", true, nervCode, "callOneTime(address)");
    await dfoManager.finalizeProposal(dfoHubManager.dfos.NERV, nervProposal);
    });
});