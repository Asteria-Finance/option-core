// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface MintableERC20 is IERC20 {
    function mint(address account, uint256 amount) external returns (uint);
}

contract MockUniswapRouterForETH is Ownable {
    using SafeMath for uint256;
    AggregatorV3Interface public priceProvider;
    MintableERC20 private usdt;

    uint256 internal constant USDT_DECIMALS = 1e6;
    uint256 internal constant PRICE_DECIMALS = 1e8;
    uint256 internal constant ETH_DECIMALS = 1e18;
    uint256 internal constant DECIMAL_RATIO = 1e2;

    fallback() external payable {}
    
    receive() external payable {}

    constructor(
        MintableERC20 _usdt,
        AggregatorV3Interface pp
    ) public {
        usdt = _usdt;
        priceProvider = pp;
    }
    
    function withdrawETH() external onlyOwner {
        msg.sender.transfer(address(this).balance);
    }

    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts) {
        require(path[0] == address(usdt), "Wrong path: first address should be usdt");
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdPrice = uint256(latestPrice).div(PRICE_DECIMALS);
        amounts = new uint[](path.length);
        amounts[0] = amountOut.mul(usdPrice).div(ETH_DECIMALS).mul(USDT_DECIMALS);
    }
    
    function swapTokensForExactETH(
        uint amountOut, 
        uint amountInMax, 
        address[] calldata path, 
        address to, 
        uint deadline
    )
        external
        returns (uint[] memory amounts) 
    {
        require(deadline > 0, "wrong deadline");
        require(path[0] == address(usdt), "Wrong path: first address should be usdt");
        amounts = new uint[](path.length);
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdPrice = uint256(latestPrice).div(PRICE_DECIMALS);
        uint256 usdtAmount = amountOut.mul(usdPrice).div(ETH_DECIMALS).mul(USDT_DECIMALS);
        amounts[0] = usdtAmount;
        amounts[1] = amountOut;
        require(amountInMax > 0, "Not enough usdt to swap");
        if (address(this).balance < amounts[1]) {
            amounts[0] = 0;
            amounts[1] = 0;
        } else {
            usdt.transferFrom(to, address(this), amounts[0]);
            payable(to).transfer(amounts[1]);
        }
    }
    
    function swapExactTokensForETH(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    )
        external
        returns (uint[] memory amounts)
    {
        require(deadline > 0, "wrong deadline");
        require(path[0] == address(usdt), "Wrong path: first address should be usdt");
        amounts = new uint[](path.length);
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdPrice = uint256(latestPrice).div(PRICE_DECIMALS);
        uint256 ethAmount = amountIn.mul(1e12).div(usdPrice);
        amounts[0] = amountIn;
        amounts[1] = ethAmount;
        require(amounts[1] > amountOutMin, "Not expected amounts out");
        if (address(this).balance < ethAmount) {
            amounts[0] = 0;
            amounts[1] = 0;
        } else {
            usdt.transferFrom(to, address(this), amounts[0]);
            payable(to).transfer(amounts[1]);
        }
    }
    
    function swapExactETHForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    )
        external
        payable
        returns (uint[] memory amounts)
    {
        require(deadline > 0, "wrong deadline");
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdPrice = uint256(latestPrice).div(PRICE_DECIMALS);
        amounts = new uint[](path.length);
        amounts[0] = msg.value;
        uint256 usdtAmount = amounts[0].mul(usdPrice).div(ETH_DECIMALS).mul(USDT_DECIMALS);
        amounts[1] = usdtAmount;
        require(amounts[1] > amountOutMin, "Not expected amounts out");
        usdt.transfer(to, amounts[1]);
    }
}
