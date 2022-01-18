// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface MintableERC20 is IERC20 {
    function mint(address account, uint256 amount) external returns (uint);
}

contract MockUniswapRouterForWBTC {
    using SafeMath for uint256;
    AggregatorV3Interface public priceProvider;
    IERC20 private weth;
    MintableERC20 private wbtc;
    MintableERC20 private usdt;

    uint256 internal constant USDT_DECIMALS = 1e6;
    uint256 internal constant PRICE_DECIMALS = 1e8;
    uint256 internal constant WBTC_DECIMALS = 1e8;
    uint256 internal constant DECIMAL_RATIO = 1e2;

    constructor(
        IERC20 _weth,
        MintableERC20 _wbtc,
        MintableERC20 _usdt,
        AggregatorV3Interface pp
    ) public {
        weth = _weth;
        wbtc = _wbtc;
        usdt = _usdt;
        priceProvider = pp;
    }

    function WETH() external view returns (address) {
        return address(weth);
    }

    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts) {
        require(path[0] == address(usdt), "Wrong path: first address should be usdt");
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdPrice = uint256(latestPrice).div(PRICE_DECIMALS);
        amounts = new uint[](path.length);
        amounts[0] = amountOut.mul(usdPrice).div(WBTC_DECIMALS).mul(USDT_DECIMALS);
    }

    // swap usdt to wbtc, usdt -> eth -> wbtc path
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(deadline > 0, "wrong deadline");
        require(path[0] == address(usdt), "Wrong path: first address should be usdt");
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdPrice = uint256(latestPrice).div(PRICE_DECIMALS);
        amounts = new uint[](path.length);
        uint256 usdtAmount = amountOut.mul(usdPrice).div(WBTC_DECIMALS).mul(USDT_DECIMALS);
        amounts[0] = usdtAmount;
        amounts[1] = 0;
        amounts[2] = amountOut;
        require(amountInMax > 0, "Not enough usdt to swap");
        usdt.transferFrom(to, address(this), amounts[0]);
        wbtc.transfer(to, amounts[2]);
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(deadline > 0, "wrong deadline");
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdPrice = uint256(latestPrice).div(PRICE_DECIMALS);
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[1] = 0;
        if (path[0] == address(wbtc)) {
            // wbtc - weth - usdt
            uint256 usdtAmount = amountIn.mul(usdPrice).div(WBTC_DECIMALS).mul(USDT_DECIMALS);
            amounts[2] = usdtAmount;
            require(amounts[2] > amountOutMin, "Not expected amounts out");
            wbtc.transferFrom(to, address(this), amountIn);
            usdt.transfer(to, amounts[2]);
        } else {
            // usdt - weth - wbtc
            uint256 wbtcAmount = amountIn.mul(DECIMAL_RATIO).div(usdPrice);
            amounts[2] = wbtcAmount;
            require(amounts[2] > amountOutMin, "Not expected amounts out");
            usdt.transferFrom(to, address(this), amounts[0]);
            wbtc.transfer(to, amounts[2]);
        }
    }
}
