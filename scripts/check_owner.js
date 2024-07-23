const MyToken = artifacts.require("GuessToken");

module.exports = async function(callback) {
    try {
        // 获取已部署的合约实例
        const token = await MyToken.deployed();

        // 获取合约所有者地址（假设合约使用了OpenZeppelin的Ownable合约）
        const owner = await token.owner();

        // 输出所有者地址
        console.log("Owner address:", owner);

        callback();
    } catch (error) {
        console.error(error);
        callback(error);
    }
};
