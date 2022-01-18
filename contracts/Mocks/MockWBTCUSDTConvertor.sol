// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface MintableERC20 is IERC20 {
    function mint(address account, uint256 amount) external returns (uint);
}

contract MockWBTCUSDTConvertor {
    AggregatorV3Interface public priceProvider;
    MintableERC20 public wbtc;
    MintableERC20 public usdt;

    constructor(
        MintableERC20 _wbtc,
        MintableERC20 _usdt,
        AggregatorV3Interface pp
    ) public {
        wbtc = _wbtc;
        usdt = _usdt;
        priceProvider = pp;
    }

    function mint(uint mintAmount) external returns (uint) {
        wbtc.transferFrom(msg.sender, address(this), mintAmount);
        return mintAmount;
    }

    function redeemUnderlying(uint redeemAmount) external returns (uint) {
        wbtc.transfer(msg.sender, redeemAmount);
        return redeemAmount;
    }

    function borrow(uint borrowAmount) external returns (uint) {
        usdt.transfer(msg.sender, borrowAmount);
        return borrowAmount;
    }

    function repayBorrow(uint repayAmount) external returns (uint) {
        usdt.transferFrom(msg.sender, address(this), repayAmount);
        return repayAmount;
    }
}
