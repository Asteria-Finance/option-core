// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../Interfaces/Interfaces.sol";

/**
 * @title Asteria WBTC Liquidity Pool
 * @notice Accumulates liquidity in WBTC from LPs and distributes P&L in WBTC
 */

contract AsteriaWBTCPool is
    IERCLiquidityPool,
    Ownable,
    ReentrancyGuard,
    ERC20("Asteria WBTC LP Token", "writeWBTC")
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bool public paused = false;

    EnumerableSet.AddressSet private users;

    uint256 public constant INITIAL_RATE = 1e13;
    // decimals for usdt
    uint256 internal constant USDT_DECIMALS = 1e6;
    // decimals for price
    uint256 internal constant PRICE_DECIMALS = 1e8;
    // decimals for token
    uint256 internal constant TOKEN_DECIMALS = 1e8;
    // used for usdt transfer
    uint256 internal constant DECIMAL_RATIO = PRICE_DECIMALS / USDT_DECIMALS;
    // 2 weeks for production
    uint256 public lockupPeriod = 30;

    // token for locked amount
    uint256 public lockedAmount;
    // usdt for locked premium
    uint256 public lockedPremium;

    /** distribution of lp */
    uint256 public totalProvidedToken;
    // token amount used for margin
    uint256 public tokenAmountForMargin;
    // usdt amount for buy hedging
    uint256 public usdtAmountForHedging;
    // token amount for sell hedging
    uint256 public tokenAmountForHedging;
    // part of token used to be locked
    uint256 public marginRate = 20;
    // part of usdt usded to hedging
    uint256 public usdtHedgingRate = 40;
    // part of token used to hedging
    uint256 public tokenHedgingRate = 40;
    uint256 public WITHDRAW_RATE = 50;

    // usdt & token position for hedging
    uint256 public usdtPosition;
    uint256 public tokenPosition;

    uint256 constant private MAX_INT = 2 ** 256 - 1;
    
    struct ProfitAndLoss {
        uint256 profit;
        uint256 loss;
    }

    mapping(address => uint256) public lastProvideTimestamp;
    mapping(address => bool) public _revertTransfersInLockUpPeriod;
    mapping(address => uint256) public accProvided;
    mapping(address => uint256) public accWithdrawed;
    // record user's profit & loss
    mapping(address => ProfitAndLoss) public plOfUser;
    LockedLiquidity[] public lockedLiquidity;
    HedgingLiquidity[] public hedgingLiquidity;
    IUniswapV2Router01 public uniswapRouter;
    AggregatorV3Interface public priceProvider;
    IConvertor public convertor;
    IERC20 public override token;
    IERC20 public usdt;
    address[] public usdtToTokenPath;
    address[] public tokenToUsdtPath;
    address public admin;

    /*
     * @return _token token Address
     */
    constructor(
        IERC20 _token,
        IERC20 _usdt,
        IUniswapV2Router01 _uniswap,
        AggregatorV3Interface _priceProvider,
        IConvertor _convertor,
        address _admin
    ) public {
        token = _token;
        usdt = _usdt;
        priceProvider = _priceProvider;
        uniswapRouter = _uniswap;
        convertor = _convertor;
        admin = _admin;
        usdtToTokenPath.push(address(_usdt));
        usdtToTokenPath.push(0xc778417E063141139Fce010982780140Aa0cD5Ab);
        usdtToTokenPath.push(address(_token));
        tokenToUsdtPath.push(address(_token));
        tokenToUsdtPath.push(0xc778417E063141139Fce010982780140Aa0cD5Ab);
        tokenToUsdtPath.push(address(_usdt));
        approve();
    }

    function approve() public {
        token.approve(address(uniswapRouter), MAX_INT);
        usdt.approve(address(uniswapRouter), MAX_INT);
        token.approve(address(convertor), MAX_INT);
        usdt.approve(address(convertor), MAX_INT);
    }

    function getUsers() external view returns (address[] memory) {
        uint256 listLength = users.length();
        address[] memory result = new address[](listLength);
        for (uint256 index = 0; index < users.length(); index++) {
            result[index] = users.at(index);
        }
        return result;
    }

    /**
     * @notice Used for changing the lockup period
     * @param value New period value
     */
    function setLockupPeriod(uint256 value) external override onlyAdmin {
        require(value <= 60 days, "AsteriaWBTCPool: Lockup period is too large");
        lockupPeriod = value;
    }

    /*
     * @nonce calls by AsteriaOptions to lock and hedging funds
     * @param amount Amount of funds that should be locked in an option
     */
    function lock(uint id, uint256 amount, uint256 premium, uint8 optionType, address user) external override nonReentrant onlyOwner {
        require(id == lockedLiquidity.length, "AsteriaWBTCPool: Wrong id");

        require(
            amount <= tokenAmountForMargin,
            "AsteriaWBTCPool: Amount is too large."
        );

        lockedLiquidity.push(LockedLiquidity(amount, premium, true));
        lockedPremium = lockedPremium.add(premium);
        lockedAmount = lockedAmount.add(amount);
        tokenAmountForMargin = tokenAmountForMargin.sub(amount);
        
        plOfUser[user].loss = plOfUser[user].loss.add(premium);

        // transfer usdt
        usdt.safeTransferFrom(msg.sender, address(this), premium);
        // hedging of beta version, 0 for call, 1 for put
        if (optionType == 0) {
            _hedging(HedgingType.Buy, amount);
        } else {
            _hedging(HedgingType.Sell, amount);
        }
    }

    function _hedging(HedgingType hedgingType, uint256 amount) internal {
        if (hedgingType == HedgingType.Buy) {
            if (usdtAmountForHedging < uniswapRouter.getAmountsIn(amount, usdtToTokenPath)[0]) {
                return;
            }
            // buy token
            uint[] memory amounts = _swapUsdtForExcatToken(amount, usdtAmountForHedging);
            usdtAmountForHedging = usdtAmountForHedging.sub(amounts[0]);
            hedgingLiquidity.push(HedgingLiquidity(HedgingType.Buy, amounts[0], amounts[2], false));
            tokenPosition = tokenPosition.add(amounts[2]);
        } else {
            if (tokenAmountForHedging < amount) {
                return;
            }
            // sell token
            uint[] memory amounts = _swapExactTokenForUsdt(amount, 0);
            tokenAmountForHedging = tokenAmountForHedging.sub(amounts[0]);
            hedgingLiquidity.push(HedgingLiquidity(HedgingType.Sell, amounts[2], amounts[0], false));
            usdtPosition = usdtPosition.add(amounts[2]);
        }
    }

    /*
     * @nonce Calls by AsteriaOptions to unlock funds and detect if it needs to be liquidated
     * @param amount Amount of funds that should be unlocked in an expired option
     */
    function unlock(uint256 id) external nonReentrant onlyOwner returns (LiquidationResult memory) {
        LockedLiquidity storage ll = lockedLiquidity[id];
        require(ll.locked, "AsteriaWBTCPool: LockedLiquidity with such id has already unlocked");
        ll.locked = false;

        lockedPremium = lockedPremium.sub(ll.premium);
        usdtAmountForHedging = usdtAmountForHedging.add(ll.premium);
        lockedAmount = lockedAmount.sub(ll.amount);
        tokenAmountForMargin = tokenAmountForMargin.add(ll.amount);

        emit Profit(id, ll.premium);
        return _liquidation(id);
    }

    struct LiquidationResult {
        bool usdtProfit;
        bool usdtLoss;
        bool tokenProfit;
        bool tokenLoss;
        uint256 usdtAmount;
        uint256 tokenAmount;
    }

    // option id for every liquidation: beta version
    mapping(uint256 => LiquidationResult) public liquidationResult;

    // for beta version, actually need to calculate the derta of whole system
    function _liquidation(uint256 id) internal returns (LiquidationResult memory) {
        HedgingLiquidity storage hl = hedgingLiquidity[id];
        LiquidationResult storage lr = liquidationResult[id];
        if (!hl.liquidated) {
            if (hl.hedgingType == HedgingType.Buy) {
                // sell token to liquidate
                uint[] memory amounts = _swapExactTokenForUsdt(hl.tokenAmount, 0);
                usdtAmountForHedging = usdtAmountForHedging.add(amounts[2]);
                tokenPosition = tokenPosition.sub(amounts[0]);
                hl.liquidated = true;
                if (hl.usdtAmount < amounts[2]) {
                    lr.usdtProfit = true;
                    lr.usdtAmount = amounts[2] - hl.usdtAmount;
                    emit HedgingUsdtProfit(id, lr.usdtAmount);
                } else {
                    lr.usdtLoss = true;
                    lr.usdtAmount = hl.usdtAmount - amounts[2];
                    emit HedgingUsdtLoss(id, lr.usdtAmount);
                }
            } else if (hl.hedgingType == HedgingType.Sell) {
                // buy token to liquidate
                uint[] memory amounts = _swapExactUsdtForToken(hl.usdtAmount, 0);
                tokenAmountForHedging = tokenAmountForHedging.add(amounts[2]);
                usdtPosition = usdtPosition.sub(amounts[0]);
                hl.liquidated = true;
                if (hl.tokenAmount < amounts[2]) {
                    lr.tokenProfit = true;
                    lr.tokenAmount = amounts[2] - hl.tokenAmount;
                    emit HedgingTokenProfit(id, lr.tokenAmount);
                } else {
                    lr.tokenLoss = true;
                    lr.tokenAmount = hl.tokenAmount - amounts[2];
                    emit HedgingTokenLoss(id, lr.tokenAmount);
                }
            }
            return lr;
        }
    }

    // for mannually liquidation by admin
    function liquidation(uint256 id) external onlyAdmin {
        _liquidation(id);
    }

    // for mannually hedging by admin
    function hedging(HedgingType hedgingType, uint256 amount) external onlyAdmin {
        _hedging(hedgingType, amount);
    }

    function rebase() external onlyAdmin {
        _rebase();
    }
    
    function testRebase() view public returns(uint256 tokenDiffer, uint256 usdtAmount, uint256 usdtDiffer, uint256 tokenAmount) {
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 hedgingUsdtConverted = _calcUsdtForHedgingValue();
        uint256 avaliableTokenAmount = tokenAmountForMargin.add(tokenAmountForHedging);
        uint256 expectedHedgingUsdt = 0;
        if (hedgingUsdtConverted == 0) {
            expectedHedgingUsdt = totalProvidedToken.mul(usdtHedgingRate).div(100);
        } else {
            expectedHedgingUsdt = avaliableTokenAmount.add(hedgingUsdtConverted).mul(usdtHedgingRate).div(100);
        }
        uint256 usdPrice = uint256(latestPrice).div(PRICE_DECIMALS);
        if (hedgingUsdtConverted < expectedHedgingUsdt) {
            tokenDiffer = expectedHedgingUsdt.sub(hedgingUsdtConverted);
            usdtAmount = tokenDiffer.mul(usdPrice).div(TOKEN_DECIMALS).mul(USDT_DECIMALS);
        } else if (hedgingUsdtConverted > expectedHedgingUsdt) {
            usdtDiffer = hedgingUsdtConverted.sub(expectedHedgingUsdt).mul(usdPrice).mul(USDT_DECIMALS);
            tokenAmount = hedgingUsdtConverted.sub(expectedHedgingUsdt);
        }
    }

    function _rebase() internal {
        // convert balance of usdt to token, and rebase the distribution of assets
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 hedgingUsdtConverted = _calcUsdtForHedgingValue();
        uint256 avaliableTokenAmount = tokenAmountForMargin.add(tokenAmountForHedging);
        uint256 expectedHedgingUsdt = 0;
        if (hedgingUsdtConverted == 0) {
            expectedHedgingUsdt = totalProvidedToken.mul(usdtHedgingRate).div(100);
        } else {
            expectedHedgingUsdt = avaliableTokenAmount.add(hedgingUsdtConverted).mul(usdtHedgingRate).div(100);
        }
        uint256 usdPrice = uint256(latestPrice).div(PRICE_DECIMALS);
        uint256 tokenRate = marginRate.add(tokenHedgingRate);
        if (hedgingUsdtConverted < expectedHedgingUsdt) {
            uint256 tokenDiffer = expectedHedgingUsdt.sub(hedgingUsdtConverted);
            if (token.balanceOf(address(this)) < tokenDiffer) {
                emit RebaseFail(address(token), tokenDiffer);
                return;
            }
            uint256 usdtAmount = tokenDiffer.mul(usdPrice).div(TOKEN_DECIMALS).mul(USDT_DECIMALS);
            uint256 convertedUsdt = _convertTokenToUsdt(tokenDiffer, usdtAmount);
            usdtAmountForHedging = usdtAmountForHedging.add(convertedUsdt);
            avaliableTokenAmount = expectedHedgingUsdt.mul(tokenRate).div(usdtHedgingRate);
            emit RebaseSuccess(address(token), tokenDiffer);
        } else if (hedgingUsdtConverted > expectedHedgingUsdt) {
            uint256 usdtDiffer = hedgingUsdtConverted.sub(expectedHedgingUsdt).mul(usdPrice).div(TOKEN_DECIMALS).mul(USDT_DECIMALS);
            if (usdt.balanceOf(address(this)) < usdtDiffer) {
                emit RebaseFail(address(usdt), usdtDiffer);
                return;
            }
            uint256 tokenAmount = hedgingUsdtConverted.sub(expectedHedgingUsdt);
            uint256 convertedToken = _convertUsdtToToken(usdtDiffer, tokenAmount);
            avaliableTokenAmount = avaliableTokenAmount.add(convertedToken);
            usdtAmountForHedging = expectedHedgingUsdt;
            emit RebaseSuccess(address(usdt), usdtDiffer);
        }
        if (usdtAmountForHedging != usdt.balanceOf(address(this)).sub(usdtPosition).sub(lockedPremium)) {
            usdtAmountForHedging = usdt.balanceOf(address(this)).sub(usdtPosition).sub(lockedPremium);
        }
        if (avaliableTokenAmount != token.balanceOf(address(this)).sub(tokenPosition)) {
            avaliableTokenAmount = token.balanceOf(address(this)).sub(tokenPosition);
        }
        tokenAmountForMargin = avaliableTokenAmount.mul(marginRate).div(tokenRate);
        tokenAmountForHedging = avaliableTokenAmount.sub(tokenAmountForMargin);
    }

    /*
     * @nonce calls by AsteriaOptions to unlock the premiums after an option's expiraton
     * @param to Provider
     * @param amount Amount of premiums that should be unlocked
     */
    /*
     * @nonce calls by AsteriaOptions to send funds to liquidity providers after an option's expiration
     * @param to Provider
     * @param amount Funds that should be sent
     */
    function send(
        uint8 optType,
        uint id,
        address payable to,
        uint256 profitUnderlying,
        uint256 profitUsdt,
        uint256 currentPrice
    )
        external
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        LockedLiquidity storage ll = lockedLiquidity[id];
        require(ll.locked, "AsteriaWBTCPool: LockedLiquidity with such id has already unlocked");
        require(to != address(0));

        ll.locked = false;
        lockedPremium = lockedPremium.sub(ll.premium);
        lockedAmount = lockedAmount.sub(ll.amount);
        tokenAmountForMargin = tokenAmountForMargin.add(ll.amount);
        usdtAmountForHedging = usdtAmountForHedging.add(ll.premium);
        LiquidationResult memory lr = _liquidation(id);

        if (profitUsdt > usdtAmountForHedging) {
            profitUsdt = usdtAmountForHedging;
        }

        if (profitUnderlying > tokenAmountForHedging) {
            profitUnderlying = tokenAmountForHedging;
        }

        uint256 poolProfitUsdt = 0;
        uint256 poolLossUsdt = 0;
        if (optType == 0) {
            // call option
            if (profitUsdt <= (ll.premium.add(lr.usdtAmount))) {
                poolProfitUsdt = ll.premium.add(lr.usdtAmount).sub(profitUsdt);
                emit Profit(id, poolProfitUsdt);
            } else {
                poolLossUsdt = profitUsdt.sub(ll.premium).sub(lr.usdtAmount);
                emit Loss(id, poolLossUsdt);
            }
        } else {
            // put option
            uint256 lrProfitUSD = lr.tokenAmount.mul(currentPrice).div(TOKEN_DECIMALS);
            uint256 lrProfitUSDT = lrProfitUSD.div(DECIMAL_RATIO);
            uint256 poolProfitUSDT = ll.premium.add(lrProfitUSDT);
            uint256 userProfitUSD = profitUnderlying.mul(currentPrice).div(TOKEN_DECIMALS);
            uint256 userProfitUSDT = userProfitUSD.div(DECIMAL_RATIO);
            if (userProfitUSDT <= poolProfitUSDT) {
                poolProfitUsdt = poolProfitUSDT.sub(userProfitUSDT);
                emit Profit(id, poolProfitUsdt);
            } else {
                poolLossUsdt = userProfitUSDT.sub(poolProfitUSDT);
                emit Loss(id, poolLossUsdt);
            }
        }
        if(profitUsdt > 0) {
            plOfUser[to].profit = plOfUser[to].profit.add(profitUsdt);
            usdtAmountForHedging = usdtAmountForHedging.sub(profitUsdt);
        }
        usdt.safeTransfer(to, profitUsdt);
        _rebase();
        return profitUsdt;
    }

    /*
     * @nonce A provider supplies WBTC to the pool and receives writeWBTC tokens
     * @param amount Provided tokens
     * @param minMint Minimum amount of tokens that should be received by a provider.
                      Calling the provide function will require the minimum amount of tokens to be minted.
                      The actual amount that will be minted could vary but can only be higher (not lower) than the minimum value.
     * @return mint Amount of tokens to be received
     */
    function provide(uint256 amount, uint256 minMint) external whenNotPaused nonReentrant returns (uint256 mint) {
        lastProvideTimestamp[msg.sender] = block.timestamp;
        uint supply = totalSupply();
        uint balance = totalBalance();
        if (supply > 0 && balance > 0)
            mint = amount.mul(supply).div(balance);
        else
            mint = amount.mul(INITIAL_RATE);

        require(mint >= minMint, "AsteriaWBTCPool: Mint limit is too large");
        require(mint > 0, "AsteriaWBTCPool: Amount is too small");
        _mint(msg.sender, mint);
        emit Provide(msg.sender, amount, mint);

        accProvided[msg.sender] = accProvided[msg.sender].add(amount);
        totalProvidedToken = totalProvidedToken.add(amount);
        uint256 marginAmount = amount.mul(marginRate).div(100);
        uint256 hedgingAmount = amount.sub(marginAmount);
        tokenAmountForMargin = tokenAmountForMargin.add(marginAmount);
        tokenAmountForHedging = tokenAmountForHedging.add(hedgingAmount);

        require(
            token.transferFrom(msg.sender, address(this), amount),
            "AsteriaWBTCPool: Please lower the amount of premiums that you want to send."
        );

        _rebase();

        // record participants
        if (!users.contains(msg.sender)) {
            users.add(msg.sender);
        }
    }

    /*
     * @nonce Provider burns writeWBTC and receives WBTC from the pool
     * @param amount Amount of WBTC to receive
     * @param maxBurn Maximum amount of tokens that can be burned
     * @return mint Amount of tokens to be burnt
     */
    function withdraw(uint256 amount, uint256 maxBurn) external whenNotPaused nonReentrant returns (uint256 burn) {
        require(
            lastProvideTimestamp[msg.sender].add(lockupPeriod) <= block.timestamp,
            "AsteriaWBTCPool:  Withdrawal is locked up"
        );
        require(
            amount <= totalBalance().mul(WITHDRAW_RATE).div(100),
            "AsteriaWBTCPool: You are trying to unlock more funds than withdraw rate"
        );

        require(
            amount <= tokenAmountForMargin.add(tokenAmountForHedging),
            "AsteriaWBTCPool: You are trying to unlock more funds than avaliable balance of contract. Please lower the amount."
        );

        burn = divCeil(amount.mul(totalSupply()), totalBalance());

        require(burn <= maxBurn, "AsteriaWBTCPool: Burn limit is too small");
        require(burn <= balanceOf(msg.sender), "AsteriaWBTCPool: Amount is too large");
        require(burn > 0, "AsteriaWBTCPool: Amount is too small");

        _burn(msg.sender, burn);
        emit Withdraw(msg.sender, amount, burn);

        uint256 accAmount = 0;

        // withdraw from margin first
        if (amount >= tokenAmountForMargin) {
            accAmount = tokenAmountForMargin;
            tokenAmountForMargin = 0;
        } else {
            accAmount = amount;
            tokenAmountForMargin = tokenAmountForMargin.sub(amount);
        }

        if (accAmount < amount) {
            tokenAmountForHedging = tokenAmountForHedging.sub(amount.sub(accAmount));
            accAmount = amount;
        }

        totalProvidedToken = totalProvidedToken.sub(amount);

        require(token.transfer(msg.sender, amount), "AsteriaWBTCPool: Insufficient funds");

        accWithdrawed[msg.sender] = accWithdrawed[msg.sender].add(amount);

        _rebase();

        // record participants
        if (!users.contains(msg.sender)) {
            users.add(msg.sender);
        }
    }

    /*
     * @nonce Returns provider's share in WBTC
     * @param account Provider's address
     * @return Provider's shareAmount and shareRate in WBTC
     */
    function shareOf(address user) public view returns (uint256, uint256) {
        uint supply = totalSupply();
        uint256 shareAmount = 0;
        uint256 shareRate = 0;
        if (supply > 0) {
            shareAmount = totalBalance().mul(balanceOf(user)).div(supply);
            shareRate = balanceOf(user).mul(1e18).div(supply);
        } else {
            shareAmount = 0;
            shareRate = 0;
        }
        return (shareAmount, shareRate);
    }

    /*
     * @nonce Returns the amount of WBTC available for withdrawals
     * @return balance Unlocked amount
     */
    function availableBalance() public view returns (uint256) {
        return _minOfAvailable();
    }

    function _minOfAvailable() internal view returns(uint256) {
        uint256 result = tokenAmountForMargin;
        uint256 usdtConverted = _calcUsdtForHedgingValue();
        if (usdtConverted < result) {
            result = usdtConverted;
        }
        if (tokenAmountForHedging < result) {
            result = tokenAmountForHedging;
        }
        return result;
    }

    /*
     * @nonce Returns the WBTC total balance provided to the pool including usdtForHedging with current price
     * @return balance Pool balance
     */
    function totalBalance() public override view returns (uint256 balance) {
        return token.balanceOf(address(this)).add(_calcUsdtForHedgingValue()).add(_calcUsdtPositionValue());
    }

    function _calcUsdtForHedgingValue() public view returns(uint256) {
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdtPrice = uint256(latestPrice).div(DECIMAL_RATIO);
        // for beta
        uint256 amounts = usdtAmountForHedging.mul(TOKEN_DECIMALS).div(usdtPrice);
        return amounts;
    }
    
    function _calcUsdtPositionValue() public view returns(uint256) {
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdtPrice = uint256(latestPrice).div(DECIMAL_RATIO);
        // for beta
        uint256 amounts = usdtPosition.mul(TOKEN_DECIMALS).div(usdtPrice);
        return amounts;
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        if (
            lastProvideTimestamp[from].add(lockupPeriod) > block.timestamp &&
            lastProvideTimestamp[from] > lastProvideTimestamp[to]
        ) {
            require(
                !_revertTransfersInLockUpPeriod[to],
                "AsteriaWBTCPool: the recipient does not accept blocked funds"
            );
            lastProvideTimestamp[to] = lastProvideTimestamp[from];
        }
    }

    function _swapUsdtForExcatToken(uint256 amountsOut, uint256 amountsIn) internal returns (uint[] memory) {
        // buy exact token
        uint[] memory amounts = uniswapRouter.swapTokensForExactTokens(
            amountsOut,
            amountsIn,
            usdtToTokenPath,
            address(this),
            block.timestamp
        );
        return amounts;
    }
    
    function _swapExactUsdtForToken(uint256 amountsIn, uint256 amountsOut) internal returns (uint[] memory) {
        // buy token with exact usdt
        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            amountsIn,
            amountsOut,
            usdtToTokenPath,
            address(this),
            block.timestamp
        );
        return amounts;
    }

    function _swapExactTokenForUsdt(uint256 amountsIn, uint256 amountsOut) internal returns (uint[] memory) {
         // sell token
        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            amountsIn,
            amountsOut,
            tokenToUsdtPath,
            address(this),
            block.timestamp
        );
        return amounts;
    }

    function _convertTokenToUsdt(uint256 tokenAmount, uint256 _usdtAmount) internal returns (uint256 usdtAmount) {
        convertor.mint(tokenAmount);
        usdtAmount = convertor.borrow(_usdtAmount);
    }

    function _convertUsdtToToken(uint256 usdtAmount, uint256 _tokenAmount) internal returns (uint256 tokenAmount) {
        convertor.repayBorrow(usdtAmount);
        tokenAmount = convertor.redeemUnderlying(_tokenAmount);
    }

    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        if (a % b != 0)
            c = c + 1;
        return c;
    }

    function setRates(uint256 _marginRate, uint256 _usdtHedgingRate, uint256 _tokenHedgingRate, uint256 _withdrawRate) external onlyAdmin {
        require(_marginRate + _usdtHedgingRate + tokenHedgingRate == 100, "AsteriaWBTCPool: wrong rates");
        require(_withdrawRate < 100, "AsteriaWBTCPool: wrong withdraw rate");
        marginRate = _marginRate;
        usdtHedgingRate = _usdtHedgingRate;
        tokenHedgingRate = _tokenHedgingRate;
        WITHDRAW_RATE = _withdrawRate;
    }

    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    modifier onlyAdmin {
        require(msg.sender == admin, "Not admin");
        _;
    }

    function setPaused(bool _paused) external onlyAdmin {
        paused = _paused;
    }

    modifier whenNotPaused {
        require(paused == false, "Contract is paused");
        _;
    }
}
