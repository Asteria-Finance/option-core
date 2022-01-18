// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface MintableERC20 is IERC20 {
    function mint(address account, uint256 amount) external returns (uint);
}

contract MockETHUSDTConvertor is Ownable {
    AggregatorV3Interface public priceProvider;
    MintableERC20 public usdt;
    address public pool;

    constructor(
        MintableERC20 _usdt,
        AggregatorV3Interface pp
    ) public {
        usdt = _usdt;
        priceProvider = pp;
    }
    
    fallback() external payable {}
    
    receive() external payable {}
    
    function setPool(address _pool) external onlyOwner {
        pool = _pool;
    }
    
    function withdrawETH() external onlyOwner {
        msg.sender.transfer(address(this).balance);
    }

    function mintWithETH() external payable returns (uint) {
        return msg.value;
    }

    function redeemUnderlying(uint redeemAmount) external returns (uint) {
        require(msg.sender == pool, "MockETHUSDTConvertor: wrong sender");
        if (redeemAmount > address(this).balance) {
            redeemAmount = address(this).balance;
        }
        msg.sender.transfer(redeemAmount);
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
