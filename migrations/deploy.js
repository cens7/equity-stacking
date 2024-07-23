// const { ethers, upgrades } = require("hardhat");
//
// async function main() {
//     const GuessTokenV2 = await ethers.getContractFactory("GuessTokenV2");
//     console.log("Upgrading GuessToken...");
//     await upgrades.upgradeProxy(DEPLOYED_PROXY_ADDRESS, GuessTokenV2);
//     console.log("GuessToken upgraded");
// }
//
// main()
//     .then(() => process.exit(0))
//     .catch((error) => {
//         console.error(error);
//         process.exit(1);
//     });