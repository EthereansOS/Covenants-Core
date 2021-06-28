var fs = require('fs');
var path = require('path');

module.exports = async function buildOSStuff(rewardToken) {
    var contracts = JSON.parse(fs.readFileSync(path.resolve(__dirname, 'contracts.json'), 'utf-8'));

    var itemInteroperableInterface = new web3.eth.Contract(contracts.ItemInteroperableInterfaceABI, knowledgeBase.osTokenAddress);

    var itemMainInterface = new web3.eth.Contract(contracts.ItemMainInterfaceABI, await itemInteroperableInterface.methods.mainInterface().call());

    var itemId = await itemInteroperableInterface.methods.itemId().call();
    var itemData = await itemMainInterface.methods.item(itemId).call();
    var collectionId = itemData.collectionId;
    var collectionData = await itemMainInterface.methods.collection(collectionId).call();
    collectionData = {...collectionData };

    var MultipleHostPerSingleItem = {
        abi: contracts.MultipleHostPerSingleItemABI,
        bin: contracts.MultipleHostPerSingleItemBIN
    };
    var multipleHostPerSingleItem = await new web3.eth.Contract(MultipleHostPerSingleItem.abi).deploy({ data: MultipleHostPerSingleItem.bin, arguments: ["0x"] }).send(blockchainConnection.getSendingOptions());

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
        collectionId, [utilities.voidEthereumAddress, "", "", ""],
        [],
        data
    ]);
    data = web3.eth.abi.encodeParameters(["address", "bytes"], [itemMainInterface.options.address, data]);
    data = web3.eth.abi.encodeParameters(["address", "bytes"], [utilities.voidEthereumAddress, data]);
    var ethOSTokensCollection = await new web3.eth.Contract(IndividualHostPerItemCollection.abi).deploy({ data: IndividualHostPerItemCollection.bin, arguments: [data] }).send(blockchainConnection.getSendingOptions());
    assert.equal(await ethOSTokensCollection.methods.itemHost(itemId).call(), multipleHostPerSingleItem.options.address);

    data = web3.eth.abi.encodeParameters(["address", "uint256", "bytes"], [ethOSTokensCollection.options.address, itemId, "0x"]);
    data = web3.eth.abi.encodeParameters(["address", "bytes"], [accounts[0], data]);
    await multipleHostPerSingleItem.methods.lazyInit(data).send(blockchainConnection.getSendingOptions());

    var OSFixedInflationExtension = await compile('../resources/OS/OSFixedInflationExtension');
    var osFixedInflationExtension = await new web3.eth.Contract(OSFixedInflationExtension.abi).deploy({ data: OSFixedInflationExtension.bin }).send(blockchainConnection.getSendingOptions());

    var osMinterAuthorized = osFixedInflationExtension.options.address;
    try {
        await blockchainConnection.unlockAccounts(osMinterAuthorized);
    } catch (e) {}

    var mintSelector = web3.utils.sha3('mint(address,uint256)').substring(0, 10);
    var batchMintSelector = web3.utils.sha3('batchMint(address[],uint256[])').substring(0, 10);
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(await multipleHostPerSingleItem.methods.host().call(), multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(await multipleHostPerSingleItem.methods.host().call(), multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    await catchCall(multipleHostPerSingleItem.methods.setAuthorized(osMinterAuthorized, true).send(blockchainConnection.getSendingOptions({ from: accounts[1] })), "unauthorized");
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    await multipleHostPerSingleItem.methods.setAuthorized(osFixedInflationExtension.options.address, true).send(blockchainConnection.getSendingOptions());
    assert(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call());
    assert(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call());

    var OSFarmExtension = await compile('../resources/OS/OSFarmExtension');
    var osFarmExtension = await new web3.eth.Contract(OSFarmExtension.abi).deploy({ data: OSFarmExtension.bin }).send(blockchainConnection.getSendingOptions());

    osMinterAuthorized = osFarmExtension.options.address;
    try {
        await blockchainConnection.unlockAccounts(osMinterAuthorized);
    } catch (e) {}

    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(await multipleHostPerSingleItem.methods.host().call(), multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(await multipleHostPerSingleItem.methods.host().call(), multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    await catchCall(multipleHostPerSingleItem.methods.setAuthorized(osMinterAuthorized, true).send(blockchainConnection.getSendingOptions({ from: accounts[1] })), "unauthorized");
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call()));
    assert(!(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call()));
    await multipleHostPerSingleItem.methods.setAuthorized(osFarmExtension.options.address, true).send(blockchainConnection.getSendingOptions());
    assert(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, mintSelector, '0x', 0).call());
    assert(await multipleHostPerSingleItem.methods.subjectIsAuthorizedFor(osMinterAuthorized, multipleHostPerSingleItem.options.address, batchMintSelector, '0x', 0).call());

    var oldHost = collectionData.host;
    await blockchainConnection.unlockAccounts(oldHost);
    collectionData.host = ethOSTokensCollection.options.address;
    await catchCall(itemMainInterface.methods.setCollectionsMetadata([collectionId], [collectionData]), "unauthorized");
    await itemMainInterface.methods.setCollectionsMetadata([collectionId], [collectionData]).send(blockchainConnection.getSendingOptions({ from: oldHost }));
    collectionData = await itemMainInterface.methods.collection(collectionId).call();
    assert.notStrictEqual(oldHost, collectionData.host);
    assert.equal(ethOSTokensCollection.options.address, collectionData.host);

    return {
        fixedInflationExtensionAddress: osFixedInflationExtension.options.address,
        fixedInflationExtensionLazyInitData: osFixedInflationExtension.methods.init(accounts[0], multipleHostPerSingleItem.options.address).encodeABI(),
        farmExtensionAddress: osFarmExtension.options.address,
        farmExtensionLazyInitData: osFarmExtension.methods.init(rewardToken && rewardToken !== utilities.voidEthereumAddress, accounts[0], utilities.voidEthereumAddress, multipleHostPerSingleItem.options.address).encodeABI()
    };
}