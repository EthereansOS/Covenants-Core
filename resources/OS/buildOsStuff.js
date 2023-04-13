var {
    VOID_ETHEREUM_ADDRESS,
    VOID_BYTES32,
    blockchainCall,
    compile,
    deployContract,
    abi,
    MAX_UINT256,
    web3Utils,
    fromDecimals,
    toDecimals,
    sendBlockchainTransaction,
    calculateTransactionFee,
  } = require('@ethereansos/multiverse');

var fs = require('fs');
var path = require('path');

module.exports = async function buildOSStuff(rewardToken) {
    var contracts = JSON.parse(fs.readFileSync(path.resolve(__dirname, 'contracts.json'), 'utf-8'));

    var itemInteroperableInterface = new web3.eth.Contract(contracts.ItemInteroperableInterfaceABI, web3.currentProvider.knowledgeBase.osTokenAddress);

    var itemMainInterface = new web3.eth.Contract(contracts.ItemMainInterfaceABI, await blockchainCall(itemInteroperableInterface.methods.mainInterface));

    var itemId = await itemInteroperableInterface.methods.itemId().call();
    var itemData = await blockchainCall(itemMainInterface.methods.item, itemId);
    var collectionId = itemData.collectionId;
    var collectionData = await blockchainCall(itemMainInterface.methods.collection, collectionId);
    collectionData = {...collectionData };

    var MultipleHostPerSingleItem = {
        abi: contracts.MultipleHostPerSingleItemABI,
        bin: contracts.MultipleHostPerSingleItemBIN
    };
    var multipleHostPerSingleItem = await deployContract(new web3.eth.Contract(MultipleHostPerSingleItem.abi), MultipleHostPerSingleItem.bin, ["0x"]);

    var IndividualHostPerItemCollection = {
        abi: contracts.IndividualHostPerItemCollectionABI,
        bin: contracts.IndividualHostPerItemCollectionBIN
    };
    var data = web3.eth.abi.encodeParameters(["uint256[]", "address[]"], [
        [itemId],
        [multipleHostPerSingleItem.options.address]
    ]);
    data = abi.encode([
        "bytes32",
        "tuple(address,string,string,string)",
        "tuple(tuple(address,string,string,string),bytes32,uint256,address[],uint256[])[]",
        "bytes"
    ], [
        collectionId, [VOID_ETHEREUM_ADDRESS, "", "", ""],
        [],
        data
    ]);
    data = web3.eth.abi.encodeParameters(["address", "bytes"], [itemMainInterface.options.address, data]);
    data = web3.eth.abi.encodeParameters(["address", "bytes"], [VOID_ETHEREUM_ADDRESS, data]);
    var ethOSTokensCollection = await deployContract(new web3.eth.Contract(IndividualHostPerItemCollection.abi), IndividualHostPerItemCollection.bin, [data]);
    assert.equal(await ethOSTokensCollection.methods.itemHost(itemId).call(), multipleHostPerSingleItem.options.address);

    data = web3.eth.abi.encodeParameters(["address", "uint256", "bytes"], [ethOSTokensCollection.options.address, itemId, "0x"]);
    data = web3.eth.abi.encodeParameters(["address", "bytes"], [accounts[0], data]);
    await blockchainCall(multipleHostPerSingleItem.methods.lazyInit, data);

    var OSFixedInflationExtension = await compile('../resources/OS/OSFixedInflationExtension');
    var osFixedInflationExtension = await deployContract(new web3.eth.Contract(OSFixedInflationExtension.abi), OSFixedInflationExtension.bin);

    var osMinterAuthorized = osFixedInflationExtension.options.address;
    try {
        await web3.currentProvider.unlockAccounts(osMinterAuthorized);
    } catch (e) {}

    var mintSelector = web3.utils.sha3('mint(address,uint256)').substring(0, 10);
    var batchMintSelector = web3.utils.sha3('batchMint(address[],uint256[])').substring(0, 10);
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(await multipleHostPerSingleItem.methods.host().call(), multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(await multipleHostPerSingleItem.methods.host().call(), multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    await assert.catchCall(blockchainCall(multipleHostPerSingleItem.methods.setAuthorized, osMinterAuthorized, true, { from: accounts[1] }), "unauthorized");
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    await blockchainCall(multipleHostPerSingleItem.methods.setAuthorized, osFixedInflationExtension.options.address, true);
    assert(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call());
    assert(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call());

    var OSFarmExtension = await compile('../resources/OS/OSFarmExtension');
    var osFarmExtension = await deployContract(new web3.eth.Contract(OSFarmExtension.abi), OSFarmExtension.bin);

    osMinterAuthorized = osFarmExtension.options.address;
    try {
        await web3.currentProvider.unlockAccounts(osMinterAuthorized);
    } catch (e) {}

    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(await multipleHostPerSingleItem.methods.host().call(), multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(await multipleHostPerSingleItem.methods.host().call(), multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    await assert.catchCall(blockchainCall(multipleHostPerSingleItem.methods.setAuthorized, osMinterAuthorized, true, { from: accounts[1] }), "unauthorized");
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    await blockchainCall(multipleHostPerSingleItem.methods.setAuthorized, osFarmExtension.options.address, true);
    assert(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call());
    assert(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call());

    var oldHost = collectionData.host;
    await web3.currentProvider.unlockAccounts(oldHost);
    collectionData.host = ethOSTokensCollection.options.address;
    await assert.catchCall(blockchainCall(itemMainInterface.methods.setCollectionsMetadata, [collectionId], [collectionData]), "unauthorized");

    // FIXME: RuntimeError: VM Exception while processing transaction: revert Invalid Host
    // var realCollectionData = await blockchainCall(itemMainInterface.methods.collection, collectionId);
    // console.log("oldHost before", oldHost);
    // oldHost = realCollectionData.host;
    // console.log("oldHost after", oldHost);
    // await blockchainCall(itemMainInterface.methods.setCollectionsMetadata, [collectionId], [collectionData], { from: oldHost });
    // collectionData = await blockchainCall(itemMainInterface.methods.collection, collectionId);
    // assert.notStrictEqual(oldHost, collectionData.host);
    // assert.equals(ethOSTokensCollection.options.address, collectionData.host);

    return {
        fixedInflationExtensionAddress: osFixedInflationExtension.options.address,
        fixedInflationExtensionLazyInitData: osFixedInflationExtension.methods.init(accounts[0], multipleHostPerSingleItem.options.address).encodeABI(),
        farmExtensionAddress: osFarmExtension.options.address,
        farmExtensionLazyInitData: osFarmExtension.methods.init(rewardToken && rewardToken !== VOID_ETHEREUM_ADDRESS, accounts[0], VOID_ETHEREUM_ADDRESS, multipleHostPerSingleItem.options.address).encodeABI()
    };
}