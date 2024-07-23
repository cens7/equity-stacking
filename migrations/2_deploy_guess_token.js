const { deployProxy } = require('@openzeppelin/truffle-upgrades');
const GuessToken = artifacts.require("GuessToken");

module.exports = async function (deployer, network, accounts) {
    const BTCUSDPriceFeed = {
        'linea_mainnet': '0x7A99092816C8BD5ec8ba229e3a6E6Da1E628E1F9', // Linea主网BTC/USD价格预言机
        'linea_testnet': '0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43', // Linea测试网BTC/USD价格预言机
        // ... 其他网络的价格预言机地址 ...
    };

    const priceFeedAddress = BTCUSDPriceFeed[network] || BTCUSDPriceFeed['linea_testnet']; // 默认使用Linea测试网

    await deployProxy(GuessToken, [priceFeedAddress], { deployer, initializer: 'initialize' });
    console.log('GuessToken deployed');
};