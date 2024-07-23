const MyToken = artifacts.require("GuessToken");
const { ethers } = require("ethers");

module.exports = async function(callback) {
    try {
        // 获取已部署的合约实例
        const token = await MyToken.deployed();

        // 调用 mint 函数（假设mint函数在合约中定义为：function mint(address to, uint256 amount) public onlyOwner）
        const amount = ethers.utils.parseUnits("20", 18); // 表示20 * 10^18
        const result = await token.mint("0xC6cDE2Ad0c15291b3db62D6e9595216ed43cdb63", amount, { from: "0x606Cb614e213a104D65771BdC4D97Fa11D14cdaf" });

        // 输出交易结果
        console.log(result);

        callback();
    } catch (error) {
        console.error(error);
        callback(error);
    }
};
