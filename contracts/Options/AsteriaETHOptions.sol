// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../Pool/AsteriaETHPool.sol";
import "./OptionsPrice.sol";

contract AsteriaETHOptions is Ownable, IAsteriaOption, ERC1155 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bool public paused = false;

    EnumerableSet.AddressSet private users;

    IAsteriaERC20FeePool public settlementFeeRecipient;
    Option[] public options;
    uint256 public impliedVolRate;
    uint256 public optionCollateralizationRatio = 100;
    // decimals for price
    uint256 internal constant PRICE_DECIMALS = 1e8;
    // decimals for token
    uint256 internal constant TOKEN_DECIMALS = 1e18;
    // decimals for usdt
    uint256 internal constant USDT_DECIMALS = 1e6;
    // used for usdt transfer
    uint256 internal constant DECIMAL_RATIO = PRICE_DECIMALS / USDT_DECIMALS;
    uint256 public OPTION_SIZE = 1e16;
    uint256 internal contractCreationTimestamp;
    uint256 constant private MAX_INT = 2 ** 256 - 1;
    AggregatorV3Interface public priceProvider;
    AsteriaETHPool public pool;
    OptionsPrice public optionsPriceCalculator;
    IERC20 public usdt;
    string private _uri;

    struct UserInfo {
        Option[] options;
        // optionID => index
        mapping(uint256 => uint256) slot;
    }

    mapping(address => UserInfo) private userInfo;

    function getUsers() external view returns (address[] memory) {
        uint256 listLength = users.length();
        address[] memory result = new address[](listLength);
        for (uint256 index = 0; index < users.length(); index++) {
            result[index] = users.at(index);
        }
        return result;
    }

    function getOptions() external view returns (Option[] memory) {
        return options;
    }

    function getUserOptions(address account) view public returns (Option[] memory) {
        return userInfo[account].options;
    }

    constructor(
        AggregatorV3Interface _priceProvider,
        IUniswapV2Router01 _uniswap,
        ERC20 _usdt,
        IAsteriaERC20FeePool _settlementFeeRecipient,
        OptionsPrice _optionsPriceCalculator,
        IConvertor _convertor,
        string memory uri_
    )
        public
        ERC1155(uri_)
    {
        _uri = uri_;
        pool = new AsteriaETHPool(
            _usdt,
            _uniswap,
            _priceProvider,
            _convertor,
            address(msg.sender)
        );
        usdt = _usdt;
        priceProvider = _priceProvider;
        settlementFeeRecipient = _settlementFeeRecipient;
        impliedVolRate = 5599413631;
        optionsPriceCalculator = _optionsPriceCalculator;
        contractCreationTimestamp = block.timestamp;
        approve();
    }

    function approve() public {
        usdt.approve(address(pool), MAX_INT);
        usdt.approve(address(settlementFeeRecipient), MAX_INT);
    }

    function transferPoolOwnership() external onlyOwner {
        require(block.timestamp < contractCreationTimestamp + 30 days);
        pool.transferOwnership(owner());
    }

    /**
     * @notice Used for adjusting the options prices while balancing asset's implied volatility rate
     * @param value New IVRate value
     */
    function setImpliedVolRate(uint256 value) external onlyOwner {
        require(value >= 1000, "AsteriaETHOptions: ImpliedVolRate limit is too small");
        impliedVolRate = value;
    }

    /**
     * @notice Used for changing settlementFeeRecipient
     * @param recipient New settlementFee recipient address
     */
    function setSettlementFeeRecipient(IAsteriaERC20FeePool recipient) external onlyOwner {
        require(address(recipient) != address(0));
        settlementFeeRecipient = recipient;
    }

    /**
     * @notice Used for changing option collateralization ratio
     * @param value New optionCollateralizationRatio value
     */
    function setOptionCollaterizationRatio(uint value) external onlyOwner {
        require(50 <= value && value <= 100, "wrong value");
        optionCollateralizationRatio = value;
    }

    function create(
        uint256 period,
        uint256 amount,
        uint256 strike,
        OptionType optionType
    )
        whenNotPaused
        external
        returns (uint256 optionID)
    {
        require(amount >= 1, "AsteriaETHOptions: invalid amount of option");
        (uint256 totalUSD, uint256 settlementFee, uint256 currentPrice) = fees(period, amount, strike, optionType);
        require(
            optionType == OptionType.Call || optionType == OptionType.Put,
            "AsteriaETHOptions: Wrong option type"
        );
        require(period >= 1 days, "AsteriaETHOptions: Period is too short");
        require(period <= 4 weeks, "AsteriaETHOptions: Period is too long");

        uint256 strikeAmount = amount.mul(OPTION_SIZE);
        optionID = options.length;

        Option memory option = Option(
            optionID,
            State.Active,
            msg.sender,
            strike,
            amount,
            strikeAmount.mul(optionCollateralizationRatio).div(100),
            totalUSD / DECIMAL_RATIO,
            block.timestamp,
            block.timestamp + period,
            0,
            optionType,
            0,
            0,
            currentPrice
        );

        options.push(option);
        userInfo[msg.sender].options.push(option);
        userInfo[msg.sender].slot[optionID] = userInfo[msg.sender].options.length - 1;

        usdt.safeTransferFrom(msg.sender, address(this), option.premium);
        uint256 settleUsdt = settlementFee / DECIMAL_RATIO;
        settlementFeeRecipient.sendProfit(settleUsdt);
        pool.lock(
            optionID,
            option.lockedAmount,
            option.premium - settleUsdt,
            uint8(optionType),
            msg.sender
        );

        // mint NFT
        _mint(msg.sender, optionID, 1, "");

        // record participants
        if (!users.contains(msg.sender)) {
            users.add(msg.sender);
        }

        emit Create(
            optionID,
            msg.sender,
            option.strike,
            option.amount,
            option.lockedAmount,
            option.premium,
            option.creationTimestamp,
            option.expiration,
            option.optionType,
            settlementFee
        );
    }

    function exercise(uint256 optionID) whenNotPaused external {
        Option storage option = options[optionID];

        require(option.expiration >= block.timestamp, "AsteriaETHOptions: Option has expired");
        require(option.holder == msg.sender, "AsteriaETHOptions: Wrong msg.sender");
        require(option.state == State.Active, "AsteriaETHOptions: Wrong state");

        option.state = State.Exercised;
        uint256 index = userInfo[msg.sender].slot[optionID];
        userInfo[msg.sender].options[index].state = State.Exercised;
        (uint256 profitUsdt, uint256 currentPrice) = payProfit(optionID);
        option.userProfitUsdt = profitUsdt;
        option.exerciseTimestamp = block.timestamp;
        option.exercisePrice = currentPrice;
        userInfo[msg.sender].options[index].userProfitUsdt = profitUsdt;
        userInfo[msg.sender].options[index].exerciseTimestamp = block.timestamp;
        userInfo[msg.sender].options[index].exercisePrice = currentPrice;

        // record participants
        if (!users.contains(msg.sender)) {
            users.add(msg.sender);
        }

        emit Exercise(msg.sender, optionID, profitUsdt, block.timestamp, currentPrice);
    }

    /**
     * @notice Unlocks an array of options
     * @param optionIDs array of options
     */
    function unlockAll(uint256[] calldata optionIDs) public {
        uint arrayLength = optionIDs.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            unlock(optionIDs[i]);
        }
    }

    /**
     * @notice Unlock funds locked in the expired options
     * @param optionID ID of the option
     */
    function unlock(uint256 optionID) public {
        Option storage option = options[optionID];
        require(option.expiration < block.timestamp, "AsteriaETHOptions: Option has not expired yet");
        require(option.state == State.Active, "AsteriaETHOptions: Option is not active");

        option.state = State.Expired;
        uint256 index = userInfo[option.holder].slot[optionID];
        userInfo[option.holder].options[index].state = State.Expired;

        pool.unlock(optionID);
        emit Expire(optionID, option.premium);
    }

    function fees(
        uint256 period,
        uint256 amount,
        uint256 strike,
        OptionType optionType
    )
        public
        view
        returns (
            uint256 totalUSD,
            uint256 settlementFee,
            uint256 currentPrice
        )
    {
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        currentPrice = uint256(latestPrice);
        uint256 optionPrice = optionsPriceCalculator.getOptionsPrice(
            impliedVolRate,
            currentPrice,
            strike,
            period,
            uint8(optionType)
        );
        settlementFee = getSettlementFee(optionPrice).mul(amount).mul(OPTION_SIZE).div(TOKEN_DECIMALS);
        uint256 actualPrice = optionPrice.mul(amount).mul(OPTION_SIZE).div(TOKEN_DECIMALS);
        totalUSD = settlementFee.add(actualPrice);
    }

    function getSettlementFee(uint256 optionPrice)
        internal
        pure
        returns (uint256 fee)
    {
        return optionPrice / 100;
    }

    function payProfit(uint optionID)
        internal
        returns (uint256 profitUsdt, uint256 currentPrice)
    {
        Option memory option = options[optionID];
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        currentPrice = uint256(latestPrice);
        uint256 underlyingAmount = 0;
        uint256 differ = 0;
        uint256 profitUSD = 0;
        uint256 profitUnderlying = 0;
        if (option.optionType == OptionType.Call) {
            require(option.strike <= currentPrice, "AsteriaWBTCOptions: Current price is too low");
            underlyingAmount = option.amount.mul(OPTION_SIZE);
            differ = currentPrice.sub(option.strike);
            profitUSD = underlyingAmount.mul(differ).div(TOKEN_DECIMALS);
            profitUnderlying = profitUSD.div(currentPrice).mul(TOKEN_DECIMALS);
        } else {
            require(option.strike >= currentPrice, "AsteriaWBTCOptions: Current price is too high");
            underlyingAmount = option.amount.mul(OPTION_SIZE);
            differ = option.strike.sub(currentPrice);
            profitUSD = underlyingAmount.mul(differ).div(TOKEN_DECIMALS);
            profitUnderlying = profitUSD.div(currentPrice).mul(TOKEN_DECIMALS);
        }
        // max payoff locked amount
        if (profitUnderlying > option.lockedAmount) {
            profitUnderlying = option.lockedAmount;
            profitUSD = profitUnderlying.mul(currentPrice).div(TOKEN_DECIMALS);
        }
        profitUsdt = pool.send(
            uint8(option.optionType),
            optionID,
            option.holder,
            profitUnderlying,
            profitUSD / DECIMAL_RATIO,
            currentPrice
        );
    }

    function setOptionSize(uint256 size) external onlyOwner {
        OPTION_SIZE = size;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) whenNotPaused override public {
        super.safeTransferFrom(from, to, id, amount, data);

        // update option info
        Option storage option = options[id];

        require(to != address(0), "AsteriaWBTCOptions: new holder address is zero");
        require(option.expiration >= block.timestamp, "AsteriaWBTCOptions: Option has expired");
        require(option.holder == msg.sender, "AsteriaWBTCOptions: Wrong msg.sender");

        option.holder = payable(to);

        // update user info
        for(uint i = 0; i < amount; i++) {
            for(uint j = 0; j < userInfo[from].options.length; j++) {
                if (userInfo[from].options[j].id == id) {
                    userInfo[to].options.push(userInfo[from].options[j]);
                    userInfo[to].slot[id] = userInfo[to].options.length - 1;
                    delete userInfo[from].options[j];
                    userInfo[from].slot[id] = userInfo[from].options.length;
                    break;
                }
            }
        }
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) whenNotPaused override public {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);

        // update option info
        for(uint index = 0; index < ids.length; index++) {
            Option storage option = options[ids[index]];

            require(to != address(0), "AsteriaWBTCOptions: new holder address is zero");
            require(option.expiration >= block.timestamp, "AsteriaWBTCOptions: Option has expired");
            require(option.holder == msg.sender, "AsteriaWBTCOptions: Wrong msg.sender");

            option.holder = payable(to);
        }

        // update user info
        for(uint index = 0; index < ids.length; index++) {
            for(uint i = 0; i < amounts[index]; i++) {
                for(uint j = 0; j < userInfo[from].options.length; j++) {
                    if (userInfo[from].options[j].id == ids[index]) {
                        userInfo[to].options.push(userInfo[from].options[j]);
                        userInfo[to].slot[ids[index]] = userInfo[to].options.length - 1;
                        delete userInfo[from].options[j];
                        userInfo[from].slot[ids[index]] = userInfo[from].options.length;
                        break;
                    }
                }
            }
        }
    }

    /**
     * @return result Square root of the number
     */
    function sqrt(uint256 x) private pure returns (uint256 result) {
        result = x;
        uint256 k = x.div(2).add(1);
        while (k < result) (result, k) = (k, x.div(k).add(k).div(2));
    }

    /**
     * @notice Convert uint256 to string
     * @param _i Unsigned integer to convert to string
     */
    function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
          return "0";
        }

        uint256 j = _i;
        uint256 ii = _i;
        uint256 len;

        // Get number of bytes
        while (j != 0) {
          len++;
          j /= 10;
        }

        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;

        // Get each individual ASCII
        while (ii != 0) {
          bstr[k--] = byte(uint8(48 + ii % 10));
          ii /= 10;
        }

        // Convert to string
        return string(bstr);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    modifier whenNotPaused {
        require(paused == false, "Contract is paused");
        _;
    }
}
