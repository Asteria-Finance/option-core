import { Contract, ContractFactory } from "ethers";
import fs from "fs";
import { ethers } from "hardhat";

// For rinkeby test
async function main(): Promise<void> {
  const oracleOnRinkeby = "0xECe365B379E1dD183B20fc5f022230C044d51404";
  const wethOnRinkeby = "0xc778417E063141139Fce010982780140Aa0cD5Ab";

  // get factories
  const USDT: ContractFactory = await ethers.getContractFactory("USDT");
  const WBTC: ContractFactory = await ethers.getContractFactory("WBTC");
  const MockWBTCUSDTConvertor: ContractFactory = await ethers.getContractFactory("MockWBTCUSDTConvertor");
  const MockUniswapRouterForWBTC: ContractFactory = await ethers.getContractFactory("MockUniswapRouterForWBTC");
  const OptionsPrice: ContractFactory = await ethers.getContractFactory("OptionsPrice");
  const AsteriaSettlementFeePool: ContractFactory = await ethers.getContractFactory("AsteriaSettlementFeePool");

  // const [owner] = await ethers.getSigners();
  // deploy
  const usdt: Contract = await USDT.deploy();
  await usdt.deployed();
  console.log("usdt deployed: ", usdt.address);
  const wbtc: Contract = await WBTC.deploy();
  await wbtc.deployed();
  console.log('wbtc deployed: ', wbtc.address);
  const convertor = await MockWBTCUSDTConvertor.deploy(wbtc.address, usdt.address, oracleOnRinkeby);
  await convertor.deployed();
  console.log("convertor deployed: ", convertor.address);
  const router = await MockUniswapRouterForWBTC.deploy(wethOnRinkeby, wbtc.address, usdt.address, oracleOnRinkeby);
  await router.deployed();
  console.log("router deployed: ", router.address);
  const optionPrice = await OptionsPrice.deploy();
  await optionPrice.deployed();
  console.log("optionPrice deployed: ", optionPrice.address);
  const feePool = await AsteriaSettlementFeePool.deploy(usdt.address);
  await feePool.deployed();
  console.log("feePool deployed: ", feePool.address);

  await usdt.functions.transfer(router.address, "1000000000000000");
  console.log("usdt transfered to router");
  await usdt.functions.transfer(convertor.address, "1000000000000000");
  console.log("usdt transfered to convertor");
  await wbtc.functions.transfer(router.address, "100000000000000000");
  console.log("wbtc transfered to router");
  await wbtc.functions.transfer(convertor.address, "100000000000000000");
  console.log("wbtc transfered to convertor");

  const addresses = {
    oracleOnRinkeby,
    wethOnRinkeby,
    usdt: usdt.address,
    wbtc: wbtc.address,
    convertor: convertor.address,
    router: router.address,
    optionPrice: optionPrice.address,
    feePool: feePool.address,
  };

  console.log(addresses);

  fs.writeFileSync(`${__dirname}/addresses.json`, JSON.stringify(addresses, null, 4));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
