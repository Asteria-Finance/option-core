pragma solidity 0.6.12;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

interface ILiquidityPool {
    struct LockedLiquidity { uint amount; uint premium; bool locked; }
    struct HedgingLiquidity { HedgingType hedgingType; uint usdtAmount; uint tokenAmount; bool liquidated; }

    enum HedgingType {Buy, Sell}

    event Profit(uint indexed id, uint amount);
    event Loss(uint indexed id, uint amount);
    event HedgingUsdtProfit(uint indexed id, uint amount);
    event HedgingTokenProfit(uint indexed id, uint amount);
    event HedgingUsdtLoss(uint indexed id, uint amount);
    event HedgingTokenLoss(uint indexed id, uint amount);
    event Provide(address indexed account, uint256 amount, uint256 writeAmount);
    event Withdraw(address indexed account, uint256 amount, uint256 writeAmount);
    event RebaseFail(address token, uint256 differ);
    event RebaseSuccess(address token, uint256 differ);

    function setLockupPeriod(uint value) external;
    function totalBalance() external view returns (uint256 amount);
    function lock(uint id, uint256 amount, uint premium, uint8 optionType, address user) external;
}

interface IERCLiquidityPool is ILiquidityPool {
    function token() external view returns (IERC20);
}

interface IAsteriaETHFeePool {
    function sendProfit() external payable;
}


interface IAsteriaERC20FeePool {
    function sendProfit(uint amount) external;
}

interface IAsteriaOption {
    event Create(
        uint256 indexed id,
        address indexed account,
        uint256 strike,
        // underlying
        uint256 amount,
        // underlying
        uint256 lockedAmount,
        // usdt
        uint256 premium,
        uint256 creationTimestamp,
        uint256 expiration,
        OptionType optionType,
        // usdt
        uint256 settlementFee
    );

    event Exercise(
        address indexed holder,
        uint256 indexed id,
        uint256 profitUsdt,
        uint256 exerciseTimestamp,
        uint256 exercisePrice
    );
    event Expire(uint256 indexed id, uint256 premium);
    enum State {Inactive, Active, Exercised, Expired}
    enum OptionType {Call, Put, Invalid}

    struct Option {
        uint256 id;
        State state;
        address payable holder;
        uint256 strike;
        uint256 amount;
        uint256 lockedAmount;
        uint256 premium;
        uint256 creationTimestamp;
        uint256 expiration;
        uint256 exerciseTimestamp;
        OptionType optionType;
        uint256 userProfitUsdt;
        uint256 exercisePrice;
        uint256 placePrice;
    }
}

interface IConvertor {
    function mintWithETH() external payable returns (uint);
    function mint(uint mintAmount) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
}
