const GuessToken = artifacts.require("GuessToken");

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

module.exports = async function (deployer, network, accounts) {
    const BTCUSDPriceFeed = {
        'linea_mainnet': '0x7A99092816C8BD5ec8ba229e3a6E6Da1E628E1F9', // Linea主网BTC/USD价格预言机
        'eth_sepolia_testnet': '0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43', // Linea测试网BTC/USD价格预言机
        'dev': '0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43',
        // ... 其他网络的价格预言机地址 ...
    };

    const priceFeedAddress = BTCUSDPriceFeed[network];
    if (!priceFeedAddress) {
        throw new Error(`No price feed address configured for network: ${network}`);
    }

    console.log(`Deploying GuessToken with price feed: ${priceFeedAddress}`);

    try {
        await sleep(5000); // 增加延迟，避免过多请求导致的错误
        // const instance = await deployProxy(GuessToken, [priceFeedAddress], { deployer, initializer: 'initialize' });
        const instance = await deployer.deploy(GuessToken, priceFeedAddress);
        console.log('GuessToken deployed at:', instance.address);
    } catch (error) {
        console.error('Deployment failed:', error);
        throw error;
    }
};
