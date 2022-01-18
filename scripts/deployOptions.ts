import { Contract, ContractFactory } from "ethers";
// import fs from "fs";
// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import addresses from './addresses.json';

async function main(): Promise<void> {
  const oracleOnRinkeby = "0xECe365B379E1dD183B20fc5f022230C044d51404";
  const uri = "https://asteria.finance/";

  const AsteriaWBTCOptions: ContractFactory = await ethers.getContractFactory("AsteriaWBTCOptions");

  const options: Contract = await AsteriaWBTCOptions.deploy(
    oracleOnRinkeby,
    addresses.router,
    addresses.wbtc,
    addresses.usdt,
    addresses.feePool,
    addresses.optionPrice,
    addresses.convertor,
    uri,
    {
      gasLimit: 9999999,
    },
  );
  await options.deployed();
  console.log("options deployed: ", options.address);
  const pool = await options.pool();
  console.log('pool address', pool);
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
