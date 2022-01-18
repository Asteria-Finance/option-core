
// File: contracts/Modules/SmallNumbers.sol

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

/**
 * Implementation of a Fraction number operation library.
 */
library SmallNumbers {
//    using Fraction for fractionNumber;
    int256 constant private sqrtNum = 1<<120;
    int256 constant private shl = 80;
    uint8 constant private PRECISION   = 32;  // fractional bits
    uint256 constant public FIXED_ONE = uint256(1) << PRECISION; // 0x100000000
    int256 constant public FIXED_64 = 1 << 64; // 0x100000000
    uint256 constant private FIXED_TWO = uint256(2) << PRECISION; // 0x200000000
    int256 constant private FIXED_SIX = int256(6) << PRECISION; // 0x200000000
    uint256 constant private MAX_VAL   = uint256(1) << (256 - PRECISION); // 0x0000000100000000000000000000000000000000000000000000000000000000

    /**
     * @dev Standard normal cumulative distribution function
     */
    function normsDist(int256 xNum) internal pure returns (int256) {
        bool _isNeg = xNum<0;
        if (_isNeg) {
            xNum = -xNum;
        }
        if (xNum > FIXED_SIX){
            return _isNeg ? 0 : int256(FIXED_ONE);
        }
        // constant int256 b1 = 1371733226;
        // constant int256 b2 = -1531429783;
        // constant int256 b3 = 7651389478;
        // constant int256 b4 = -7822234863;
        // constant int256 b5 = 5713485167;
        //t = 1.0/(1.0 + p*x);
        int256 p = 994894385;
        int256 t = FIXED_64/(((p*xNum)>>PRECISION)+int256(FIXED_ONE));
        //double val = 1 - (1/(Math.sqrt(2*Math.PI))  * Math.exp(-1*Math.pow(a, 2)/2)) * (b1*t + b2 * Math.pow(t,2) + b3*Math.pow(t,3) + b4 * Math.pow(t,4) + b5 * Math.pow(t,5) );
        //1.0 - (-x * x / 2.0).exp()/ (2.0*pi()).sqrt() * t * (a1 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429)))) ;
        xNum=xNum*xNum/int256(FIXED_TWO);
        xNum = int256(7359186145390886912/fixedExp(uint256(xNum)));
        int256 tt = t;
        int256 All = 1371733226*tt;
        tt = (tt*t)>>PRECISION;
        All += -1531429783*tt;
        tt = (tt*t)>>PRECISION;
        All += 7651389478*tt;
        tt = (tt*t)>>PRECISION;
        All += -7822234863*tt;
        tt = (tt*t)>>PRECISION;
        All += 5713485167*tt;
        xNum = (xNum*All)>>64;
        if (!_isNeg) {
            xNum = uint64(FIXED_ONE) - xNum;
        }
        return xNum;
    }
    function pow(uint256 _x,uint256 _y) internal pure returns (uint256){
        _x = (ln(_x)*_y)>>PRECISION;
        return fixedExp(_x);
    }

    //This is where all your gas goes, sorry
    //Not sorry, you probably only paid 1 gwei
    function sqrt(uint x) internal pure returns (uint y) {
        x = x << PRECISION;
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    function ln(uint256 _x)  internal pure returns (uint256) {
        return fixedLoge(_x);
    }
        /**
        input range:
            [0x100000000,uint256_max]
        output range:
            [0, 0x9b43d4f8d6]
        This method asserts outside of bounds
    */
    function fixedLoge(uint256 _x) internal pure returns (uint256 logE) {
        /*
        Since `fixedLog2_min` output range is max `0xdfffffffff`
        (40 bits, or 5 bytes), we can use a very large approximation
        for `ln(2)`. This one is used since it’s the max accuracy
        of Python `ln(2)`
        0xb17217f7d1cf78 = ln(2) * (1 << 56)

        */
        //Cannot represent negative numbers (below 1)
        require(_x >= FIXED_ONE,"loge function input is too small");

        uint256 _log2 = fixedLog2(_x);
        logE = (_log2 * 0xb17217f7d1cf78) >> 56;
    }

    /**
        Returns log2(x >> 32) << 32 [1]
        So x is assumed to be already upshifted 32 bits, and
        the result is also upshifted 32 bits.

        [1] The function returns a number which is lower than the
        actual value
        input-range :
            [0x100000000,uint256_max]
        output-range:
            [0,0xdfffffffff]
        This method asserts outside of bounds
    */
    function fixedLog2(uint256 _x) internal pure returns (uint256) {
        // Numbers below 1 are negative.
        require( _x >= FIXED_ONE,"Log2 input is too small");

        uint256 hi = 0;
        while (_x >= FIXED_TWO) {
            _x >>= 1;
            hi += FIXED_ONE;
        }

        for (uint8 i = 0; i < PRECISION; ++i) {
            _x = (_x * _x) / FIXED_ONE;
            if (_x >= FIXED_TWO) {
                _x >>= 1;
                hi += uint256(1) << (PRECISION - 1 - i);
            }
        }

        return hi;
    }
    function exp(int256 _x)internal pure returns (uint256){
        bool _isNeg = _x<0;
        if (_isNeg) {
            _x = -_x;
        }
        uint256 value = fixedExp(uint256(_x));
        if (_isNeg){
            return uint256(FIXED_64) / value;
        }
        return value;
    }
    /**
        fixedExp is a ‘protected’ version of `fixedExpUnsafe`, which
        asserts instead of overflows
    */
    function fixedExp(uint256 _x) internal pure returns (uint256) {
        require(_x <= 0x386bfdba29,"exp function input is overflow");
        return fixedExpUnsafe(_x);
    }
       /**
        fixedExp
        Calculates e^x according to maclauren summation:
        e^x = 1+x+x^2/2!...+x^n/n!
        and returns e^(x>>32) << 32, that is, upshifted for accuracy
        Input range:
            - Function ok at    <= 242329958953
            - Function fails at >= 242329958954
        This method is is visible for testcases, but not meant for direct use.

        The values in this method been generated via the following python snippet:
        def calculateFactorials():
            “”"Method to print out the factorials for fixedExp”“”
            ni = []
            ni.append( 295232799039604140847618609643520000000) # 34!
            ITERATIONS = 34
            for n in range( 1,  ITERATIONS,1 ) :
                ni.append(math.floor(ni[n - 1] / n))
            print( “\n        “.join([“xi = (xi * _x) >> PRECISION;\n        res += xi * %s;” % hex(int(x)) for x in ni]))
    */
    function fixedExpUnsafe(uint256 _x) internal pure returns (uint256) {

        uint256 xi = FIXED_ONE;
        uint256 res = 0xde1bc4d19efcac82445da75b00000000 * xi;

        xi = (xi * _x) >> PRECISION;
        res += xi * 0xde1bc4d19efcb0000000000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x6f0de268cf7e58000000000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x2504a0cd9a7f72000000000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x9412833669fdc800000000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x1d9d4d714865f500000000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x4ef8ce836bba8c0000000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0xb481d807d1aa68000000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x16903b00fa354d000000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x281cdaac677b3400000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x402e2aad725eb80000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x5d5a6c9f31fe24000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x7c7890d442a83000000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x9931ed540345280000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0xaf147cf24ce150000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0xbac08546b867d000000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0xbac08546b867d00000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0xafc441338061b8000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x9c3cabbc0056e000000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x839168328705c80000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x694120286c04a0000;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x50319e98b3d2c400;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x3a52a1e36b82020;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x289286e0fce002;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x1b0c59eb53400;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x114f95b55400;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0xaa7210d200;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x650139600;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x39b78e80;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x1fd8080;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x10fbc0;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x8c40;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x462;
        xi = (xi * _x) >> PRECISION;
        res += xi * 0x22;

        return res / 0xde1bc4d19efcac82445da75b00000000;
    }
}

// File: contracts/Options/OptionsPrice.sol

pragma solidity 0.6.12;



contract OptionsPrice is Ownable {
    uint256 constant internal Year = 365 days;
    uint256 internal ratioR2 = 4<<32;
    int256 constant public FIXED_ONE = 1 << 32; // 0x100000000

    function getOptionsPrice(
        uint256 _iv,
        uint256 currentPrice,
        uint256 strikePrice,
        uint256 expiration,
        uint8 optType
    ) public pure returns (uint256) {
        if (optType == 0) {
            return callOptionsPrice(currentPrice,strikePrice,expiration,_iv);
        }else if (optType == 1){
            return putOptionsPrice(currentPrice,strikePrice,expiration,_iv);
        }else{
            require(optType<2," Must input 0 for call option or 1 for put option");
        }
    }

    /**
     * @dev An auxiliary function, calculate parameter d1 and d2 in B_S formulas.
     * @param currentPrice current underlying price.
     * @param strikePrice option's strike price.
     * @param expiration option's expiration left time. Equal option's expiration timestamp - now.
     * @param derta implied volatility value in B-S formulas.
     */
    function calculateD1D2(uint256 currentPrice, uint256 strikePrice, uint256 expiration, uint256 derta)
            internal pure returns (int256,int256) {
        int256 d1 = 0;
        if (currentPrice > strikePrice){
            d1 = int256(SmallNumbers.fixedLoge((currentPrice<<32)/strikePrice));
        }else if (currentPrice<strikePrice){
            d1 = -int256(SmallNumbers.fixedLoge((strikePrice<<32)/currentPrice));
        }
        uint256 derta2 = (derta*derta)>>33;//0.5*derta^2
        derta2 = derta2*expiration/Year;
        d1 = d1+int256(derta2);
        derta2 = SmallNumbers.sqrt(derta2*2);
        d1 = (d1<<32)/int256(derta2);
        return (d1, d1 - int256(derta2));
    }

    /**
     * @dev An auxiliary function, calculate put option price using B_S formulas.
     * @param currentPrice current underlying price.
     * @param strikePrice option's strike price.
     * @param expiration option's expiration left time. Equal option's expiration timestamp - now.
     * @param derta implied volatility value in B-S formulas.
     */
    //L*pow(e,-rT)*(1-N(d2)) - S*(1-N(d1))
    function putOptionsPrice(uint256 currentPrice, uint256 strikePrice, uint256 expiration, uint256 derta)
                internal pure returns (uint256) {
       (int256 d1, int256 d2) = calculateD1D2(currentPrice, strikePrice, expiration, derta);
        d1 = SmallNumbers.normsDist(d1);
        d2 = SmallNumbers.normsDist(d2);
        d1 = (FIXED_ONE - d1)*int256(currentPrice);
        d2 = (FIXED_ONE - d2)*int256(strikePrice);
        d1 = d2 - d1;
        int256 minPrice = int256(currentPrice)*12884902;
        return (d1>minPrice) ? uint256(d1>>32) : currentPrice*3/1000;
    }

    /**
     * @dev An auxiliary function, calculate call option price using B_S formulas.
     * @param currentPrice current underlying price.
     * @param strikePrice option's strike price.
     * @param expiration option's expiration left time. Equal option's expiration timestamp - now.
     * @param derta implied volatility value in B-S formulas.
     */
    //S*N(d1)-L*pow(e,-rT)*N(d2)
    function callOptionsPrice(uint256 currentPrice, uint256 strikePrice, uint256 expiration, uint256 derta)
                internal pure returns (uint256) {
       (int256 d1, int256 d2) = calculateD1D2(currentPrice, strikePrice, expiration, derta);
        d1 = SmallNumbers.normsDist(d1);
        d2 = SmallNumbers.normsDist(d2);
        d1 = d1*int256(currentPrice)-d2*int256(strikePrice);
        int256 minPrice = int256(currentPrice)*12884902;
        return (d1>minPrice) ? uint256(d1>>32) : currentPrice*3/1000;
    }

    function calOptionsPriceRatio(uint256 selfOccupied,uint256 totalOccupied,uint256 totalCollateral) public pure returns (uint256){
        //r1 + 0.5
        if (selfOccupied*2<=totalOccupied){
            return 4294967296;
        }
        uint256 r1 = (selfOccupied<<32)/totalOccupied-2147483648;
        uint256 r2 = (totalOccupied<<32)/totalCollateral*2;
        //r1*r2*1.5
        r1 = (r1*r2)>>32;
        return ((r1*r1*r1)>>64)*3+4294967296;
    }
}

// File: @uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol

pragma solidity >=0.6.2;

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

// File: @chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol

pragma solidity >=0.6.0;

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function version() external view returns (uint256);

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

// File: @openzeppelin/contracts/introspection/ERC165.sol


pragma solidity >=0.6.0 <0.8.0;


/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts may inherit from this and call {_registerInterface} to declare
 * their support of an interface.
 */
abstract contract ERC165 is IERC165 {
    /*
     * bytes4(keccak256('supportsInterface(bytes4)')) == 0x01ffc9a7
     */
    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;

    /**
     * @dev Mapping of interface ids to whether or not it's supported.
     */
    mapping(bytes4 => bool) private _supportedInterfaces;

    constructor () internal {
        // Derived contracts need only register support for their own interfaces,
        // we register support for ERC165 itself here
        _registerInterface(_INTERFACE_ID_ERC165);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     *
     * Time complexity O(1), guaranteed to always use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return _supportedInterfaces[interfaceId];
    }

    /**
     * @dev Registers the contract as an implementer of the interface defined by
     * `interfaceId`. Support of the actual ERC165 interface is automatic and
     * registering its interface id is not required.
     *
     * See {IERC165-supportsInterface}.
     *
     * Requirements:
     *
     * - `interfaceId` cannot be the ERC165 invalid interface (`0xffffffff`).
     */
    function _registerInterface(bytes4 interfaceId) internal virtual {
        require(interfaceId != 0xffffffff, "ERC165: invalid interface id");
        _supportedInterfaces[interfaceId] = true;
    }
}

// File: @openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol


pragma solidity >=0.6.0 <0.8.0;


/**
 * _Available since v3.1._
 */
interface IERC1155Receiver is IERC165 {

    /**
        @dev Handles the receipt of a single ERC1155 token type. This function is
        called at the end of a `safeTransferFrom` after the balance has been updated.
        To accept the transfer, this must return
        `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
        (i.e. 0xf23a6e61, or its own function selector).
        @param operator The address which initiated the transfer (i.e. msg.sender)
        @param from The address which previously owned the token
        @param id The ID of the token being transferred
        @param value The amount of tokens being transferred
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
    */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        external
        returns(bytes4);

    /**
        @dev Handles the receipt of a multiple ERC1155 token types. This function
        is called at the end of a `safeBatchTransferFrom` after the balances have
        been updated. To accept the transfer(s), this must return
        `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
        (i.e. 0xbc197c81, or its own function selector).
        @param operator The address which initiated the batch transfer (i.e. msg.sender)
        @param from The address which previously owned the token
        @param ids An array containing ids of each token being transferred (order and length must match values array)
        @param values An array containing amounts of each token being transferred (order and length must match ids array)
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
    */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
        external
        returns(bytes4);
}

// File: @openzeppelin/contracts/token/ERC1155/IERC1155MetadataURI.sol


pragma solidity >=0.6.2 <0.8.0;


/**
 * @dev Interface of the optional ERC1155MetadataExtension interface, as defined
 * in the https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[EIP].
 *
 * _Available since v3.1._
 */
interface IERC1155MetadataURI is IERC1155 {
    /**
     * @dev Returns the URI for token type `id`.
     *
     * If the `\{id\}` substring is present in the URI, it must be replaced by
     * clients with the actual token type ID.
     */
    function uri(uint256 id) external view returns (string memory);
}

// File: @openzeppelin/contracts/introspection/IERC165.sol


pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// File: @openzeppelin/contracts/token/ERC1155/IERC1155.sol


pragma solidity >=0.6.2 <0.8.0;


/**
 * @dev Required interface of an ERC1155 compliant contract, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1155[EIP].
 *
 * _Available since v3.1._
 */
interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` tokens of token type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the amount of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids) external view returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must be have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data) external;
}

// File: @openzeppelin/contracts/token/ERC1155/ERC1155.sol


pragma solidity >=0.6.0 <0.8.0;








/**
 *
 * @dev Implementation of the basic standard multi-token.
 * See https://eips.ethereum.org/EIPS/eip-1155
 * Originally based on code by Enjin: https://github.com/enjin/erc-1155
 *
 * _Available since v3.1._
 */
contract ERC1155 is Context, ERC165, IERC1155, IERC1155MetadataURI {
    using SafeMath for uint256;
    using Address for address;

    // Mapping from token ID to account balances
    mapping (uint256 => mapping(address => uint256)) private _balances;

    // Mapping from account to operator approvals
    mapping (address => mapping(address => bool)) private _operatorApprovals;

    // Used as the URI for all token types by relying on ID substitution, e.g. https://token-cdn-domain/{id}.json
    string private _uri;

    /*
     *     bytes4(keccak256('balanceOf(address,uint256)')) == 0x00fdd58e
     *     bytes4(keccak256('balanceOfBatch(address[],uint256[])')) == 0x4e1273f4
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c5
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,uint256,bytes)')) == 0xf242432a
     *     bytes4(keccak256('safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)')) == 0x2eb2c2d6
     *
     *     => 0x00fdd58e ^ 0x4e1273f4 ^ 0xa22cb465 ^
     *        0xe985e9c5 ^ 0xf242432a ^ 0x2eb2c2d6 == 0xd9b67a26
     */
    bytes4 private constant _INTERFACE_ID_ERC1155 = 0xd9b67a26;

    /*
     *     bytes4(keccak256('uri(uint256)')) == 0x0e89341c
     */
    bytes4 private constant _INTERFACE_ID_ERC1155_METADATA_URI = 0x0e89341c;

    /**
     * @dev See {_setURI}.
     */
    constructor (string memory uri_) public {
        _setURI(uri_);

        // register the supported interfaces to conform to ERC1155 via ERC165
        _registerInterface(_INTERFACE_ID_ERC1155);

        // register the supported interfaces to conform to ERC1155MetadataURI via ERC165
        _registerInterface(_INTERFACE_ID_ERC1155_METADATA_URI);
    }

    /**
     * @dev See {IERC1155MetadataURI-uri}.
     *
     * This implementation returns the same URI for *all* token types. It relies
     * on the token type ID substitution mechanism
     * https://eips.ethereum.org/EIPS/eip-1155#metadata[defined in the EIP].
     *
     * Clients calling this function must replace the `\{id\}` substring with the
     * actual token type ID.
     */
    function uri(uint256) external view virtual override returns (string memory) {
        return _uri;
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        require(account != address(0), "ERC1155: balance query for the zero address");
        return _balances[id][account];
    }

    /**
     * @dev See {IERC1155-balanceOfBatch}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(
        address[] memory accounts,
        uint256[] memory ids
    )
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        require(accounts.length == ids.length, "ERC1155: accounts and ids length mismatch");

        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }

        return batchBalances;
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(_msgSender() != operator, "ERC1155: setting approval status for self");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address account, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[account][operator];
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    )
        public
        virtual
        override
    {
        require(to != address(0), "ERC1155: transfer to the zero address");
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, to, _asSingletonArray(id), _asSingletonArray(amount), data);

        _balances[id][from] = _balances[id][from].sub(amount, "ERC1155: insufficient balance for transfer");
        _balances[id][to] = _balances[id][to].add(amount);

        emit TransferSingle(operator, from, to, id, amount);

        _doSafeTransferAcceptanceCheck(operator, from, to, id, amount, data);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        public
        virtual
        override
    {
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
        require(to != address(0), "ERC1155: transfer to the zero address");
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: transfer caller is not owner nor approved"
        );

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            _balances[id][from] = _balances[id][from].sub(
                amount,
                "ERC1155: insufficient balance for transfer"
            );
            _balances[id][to] = _balances[id][to].add(amount);
        }

        emit TransferBatch(operator, from, to, ids, amounts);

        _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, amounts, data);
    }

    /**
     * @dev Sets a new URI for all token types, by relying on the token type ID
     * substitution mechanism
     * https://eips.ethereum.org/EIPS/eip-1155#metadata[defined in the EIP].
     *
     * By this mechanism, any occurrence of the `\{id\}` substring in either the
     * URI or any of the amounts in the JSON file at said URI will be replaced by
     * clients with the token type ID.
     *
     * For example, the `https://token-cdn-domain/\{id\}.json` URI would be
     * interpreted by clients as
     * `https://token-cdn-domain/000000000000000000000000000000000000000000000000000000000004cce0.json`
     * for token type ID 0x4cce0.
     *
     * See {uri}.
     *
     * Because these URIs cannot be meaningfully represented by the {URI} event,
     * this function emits no events.
     */
    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }

    /**
     * @dev Creates `amount` tokens of token type `id`, and assigns them to `account`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - If `account` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _mint(address account, uint256 id, uint256 amount, bytes memory data) internal virtual {
        require(account != address(0), "ERC1155: mint to the zero address");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), account, _asSingletonArray(id), _asSingletonArray(amount), data);

        _balances[id][account] = _balances[id][account].add(amount);
        emit TransferSingle(operator, address(0), account, id, amount);

        _doSafeTransferAcceptanceCheck(operator, address(0), account, id, amount, data);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_mint}.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function _mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal virtual {
        require(to != address(0), "ERC1155: mint to the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        for (uint i = 0; i < ids.length; i++) {
            _balances[ids[i]][to] = amounts[i].add(_balances[ids[i]][to]);
        }

        emit TransferBatch(operator, address(0), to, ids, amounts);

        _doSafeBatchTransferAcceptanceCheck(operator, address(0), to, ids, amounts, data);
    }

    /**
     * @dev Destroys `amount` tokens of token type `id` from `account`
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens of token type `id`.
     */
    function _burn(address account, uint256 id, uint256 amount) internal virtual {
        require(account != address(0), "ERC1155: burn from the zero address");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, account, address(0), _asSingletonArray(id), _asSingletonArray(amount), "");

        _balances[id][account] = _balances[id][account].sub(
            amount,
            "ERC1155: burn amount exceeds balance"
        );

        emit TransferSingle(operator, account, address(0), id, amount);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_burn}.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     */
    function _burnBatch(address account, uint256[] memory ids, uint256[] memory amounts) internal virtual {
        require(account != address(0), "ERC1155: burn from the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, account, address(0), ids, amounts, "");

        for (uint i = 0; i < ids.length; i++) {
            _balances[ids[i]][account] = _balances[ids[i]][account].sub(
                amounts[i],
                "ERC1155: burn amount exceeds balance"
            );
        }

        emit TransferBatch(operator, account, address(0), ids, amounts);
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning, as well as batched variants.
     *
     * The same hook is called on both single and batched variants. For single
     * transfers, the length of the `id` and `amount` arrays will be 1.
     *
     * Calling conditions (for each `id` and `amount` pair):
     *
     * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * of token type `id` will be  transferred to `to`.
     * - When `from` is zero, `amount` tokens of token type `id` will be minted
     * for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens of token type `id`
     * will be burned.
     * - `from` and `to` are never both zero.
     * - `ids` and `amounts` have the same, non-zero length.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        internal
        virtual
    { }

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    )
        private
    {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                if (response != IERC1155Receiver(to).onERC1155Received.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        private
    {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (bytes4 response) {
                if (response != IERC1155Receiver(to).onERC1155BatchReceived.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    function _asSingletonArray(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol


pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// File: @openzeppelin/contracts/utils/Address.sol


pragma solidity >=0.6.2 <0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// File: @openzeppelin/contracts/token/ERC20/SafeERC20.sol


pragma solidity >=0.6.0 <0.8.0;




/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// File: @openzeppelin/contracts/math/SafeMath.sol


pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// File: @openzeppelin/contracts/utils/Context.sol


pragma solidity >=0.6.0 <0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// File: @openzeppelin/contracts/token/ERC20/ERC20.sol

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;




/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20 {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Sets {decimals} to a value other than the default one of 18.
     *
     * WARNING: This function should only be called from the constructor. Most
     * applications that interact with token contracts will not expect
     * {decimals} to ever change, and may work incorrectly if it does.
     */
    function _setupDecimals(uint8 decimals_) internal virtual {
        _decimals = decimals_;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
}

// File: contracts/Interfaces/Interfaces.sol

pragma solidity 0.6.12;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 */







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
        uint256 expiration,
        OptionType optionType,
        // usdt
        uint256 settlementFee
    );

    event Exercise(address indexed holder, uint256 indexed id, uint256 profitUnderlying, uint256 profitUSD);
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
        uint256 expiration;
        OptionType optionType;
    }

    function options(uint) external view returns (
        uint256 id,
        State state,
        address payable holder,
        uint256 strike,
        uint256 amount,
        uint256 lockedAmount,
        uint256 premium,
        uint256 expiration,
        OptionType optionType
    );

    function tokenURI(uint256 _tokenId) external view returns (string memory);
}

interface IConvertor {
    function mintWithETH() external payable returns (uint);
    function mint(uint mintAmount) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
}

// File: @openzeppelin/contracts/utils/ReentrancyGuard.sol

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () internal {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// File: contracts/Pool/AsteriaWBTCPool.sol

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;




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
        returns (LiquidationResult memory)
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
        return lr;
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
        return token.balanceOf(address(this)).add(_calcUsdtForHedgingValue());
    }

    function _calcUsdtForHedgingValue() public view returns(uint256) {
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 usdtPrice = uint256(latestPrice).div(DECIMAL_RATIO);
        // for beta
        uint256 amounts = usdtAmountForHedging.mul(TOKEN_DECIMALS).div(usdtPrice);
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

// File: @openzeppelin/contracts/utils/EnumerableSet.sol

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

// File: contracts/Options/AsteriaWBTCOptions.sol

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;




/**
 * @title Asteria WBTC Bidirectional (Call and Put) Options
 * @notice Asteria Protocol Options Contract
 */
contract AsteriaWBTCOptions is Ownable, IAsteriaOption, ERC1155 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bool public paused = false;

    EnumerableSet.AddressSet private users;

    IAsteriaERC20FeePool public settlementFeeRecipient;
    Option[] public override options;
    uint256 public impliedVolRate;
    uint256 public optionCollateralizationRatio = 100;
    // decimals for price
    uint256 internal constant PRICE_DECIMALS = 1e8;
    // decimals for token
    uint256 internal constant TOKEN_DECIMALS = 1e8;
    // decimals for usdt
    uint256 internal constant USDT_DECIMALS = 1e6;
    // used for usdt transfer
    uint256 internal constant DECIMAL_RATIO = PRICE_DECIMALS / USDT_DECIMALS;
    uint256 public OPTION_SIZE = 1e6;
    uint256 internal contractCreationTimestamp;
    uint256 constant private MAX_INT = 2 ** 256 - 1;
    AggregatorV3Interface public priceProvider;
    AsteriaWBTCPool public pool;
    OptionsPrice public optionsPriceCalculator;
    IERC20 public wbtc;
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

    /**
     * @param _priceProvider The address of ChainLink BTC/USD price feed contract
     * @param _uniswap The address of Uniswap router contract
     * @param _wbtc The address of WBTC ERC20 token contract
     */
    constructor(
        AggregatorV3Interface _priceProvider,
        IUniswapV2Router01 _uniswap,
        ERC20 _wbtc,
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
        pool = new AsteriaWBTCPool(
            _wbtc,
            _usdt,
            _uniswap,
            _priceProvider,
            _convertor,
            address(msg.sender)
        );
        wbtc = _wbtc;
        usdt = _usdt;
        priceProvider = _priceProvider;
        settlementFeeRecipient = _settlementFeeRecipient;
        impliedVolRate = 4150595749;
        optionsPriceCalculator = _optionsPriceCalculator;
        contractCreationTimestamp = block.timestamp;
        approve();
    }

    /**
     * @notice Allows the ERC pool contract to receive and send tokens
     */
    function approve() public {
        wbtc.approve(address(pool), MAX_INT);
        wbtc.approve(address(settlementFeeRecipient), MAX_INT);
        usdt.approve(address(pool), MAX_INT);
        usdt.approve(address(settlementFeeRecipient), MAX_INT);
    }

    function tokenURI(uint256 _tokenId) external override view returns (string memory) {
        return string(abi.encodePacked(
            _uri,
            _uint2str(_tokenId),
            ".json"
        ));
    }

    /**
     * @notice For beta version to test
     */
    function transferPoolOwnership() external onlyOwner {
        require(block.timestamp < contractCreationTimestamp + 30 days);
        pool.transferOwnership(owner());
    }

    /**
     * @notice Used for adjusting the options prices while balancing asset's implied volatility rate
     * @param value New IVRate value
     */
    function setImpliedVolRate(uint256 value) external onlyOwner {
        require(value >= 1000, "AsteriaWBTCOptions: ImpliedVolRate limit is too small");
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

    /**
     * @notice Creates a new option
     * @param period Option period in seconds (1 days <= period <= 4 weeks)
     * @param amount Option amount
     * @param strike Strike price of the option
     * @param optionType Call or Put option type
     * @return optionID Created option's ID
     */
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
        require(amount >= 1, "AsteriaWBTCOptions: invalid amount of option");
        (uint256 totalUSD, uint256 settlementFee) = fees(period, amount, strike, optionType);
        require(
            optionType == OptionType.Call || optionType == OptionType.Put,
            "AsteriaWBTCOptions: Wrong option type"
        );
        require(period >= 1 days, "AsteriaWBTCOptions: Period is too short");
        require(period <= 4 weeks, "AsteriaWBTCOptions: Period is too long");

        uint256 strikeAmount = amount.mul(OPTION_SIZE);
        uint premium = totalUSD.sub(settlementFee);
        optionID = options.length;

        Option memory option = Option(
            optionID,
            State.Active,
            msg.sender,
            strike,
            amount,
            strikeAmount.mul(optionCollateralizationRatio).div(100),
            premium,
            block.timestamp + period,
            optionType
        );


        options.push(option);
        userInfo[msg.sender].options.push(option);
        userInfo[msg.sender].slot[optionID] = userInfo[msg.sender].options.length - 1;

        usdt.safeTransferFrom(msg.sender, address(this), totalUSD / DECIMAL_RATIO);

        settlementFeeRecipient.sendProfit(settlementFee / DECIMAL_RATIO);
        pool.lock(
            optionID,
            option.lockedAmount,
            option.premium / DECIMAL_RATIO,
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
            option.expiration,
            option.optionType,
            settlementFee
        );
    }

    /**
     * @notice Exercises an active option
     * @param optionID ID of your option
     */
    function exercise(uint256 optionID) whenNotPaused external {
        Option storage option = options[optionID];

        require(option.expiration >= block.timestamp, "AsteriaWBTCOptions: Option has expired");
        require(option.holder == msg.sender, "AsteriaWBTCOptions: Wrong msg.sender");
        require(option.state == State.Active, "AsteriaWBTCOptions: Wrong state");

        option.state = State.Exercised;
        uint256 index = userInfo[msg.sender].slot[optionID];
        userInfo[msg.sender].options[index].state = State.Exercised;
        (uint256 profitUnderlying, uint256 profitUSD) = payProfit(optionID);

        // record participants
        if (!users.contains(msg.sender)) {
            users.add(msg.sender);
        }

        emit Exercise(msg.sender, optionID, profitUnderlying, profitUSD);
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
        require(option.expiration < block.timestamp, "AsteriaWBTCOptions: Option has not expired yet");
        require(option.state == State.Active, "AsteriaWBTCOptions: Option is not active");

        option.state = State.Expired;
        uint256 index = userInfo[option.holder].slot[optionID];
        userInfo[option.holder].options[index].state = State.Expired;

        pool.unlock(optionID);
        emit Expire(optionID, option.premium);
    }

    /**
     * @notice Used for getting the actual options prices
     * @param period Option period in seconds (1 days <= period <= 4 weeks)
     * @param amount Option amount
     * @param strike Strike price of the option
     * @return totalUSD Total USDT to be paid (PRICE_DECIMALS)
     * @return settlementFee Amount to be distributed to the Asteria token holders
     */
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
            uint256 settlementFee
        )
    {
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 currentPrice = uint256(latestPrice);
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

    /**
     * @notice Calculates settlementFee
     * @return fee Settlement fee amount
     */
    function getSettlementFee(uint256 optionPrice)
        internal
        pure
        returns (uint256 fee)
    {
        return optionPrice / 100;
    }

    /**
     * @notice Sends profits in WBTC from the WBTC pool to an option holder's address
     * @param optionID A specific option contract id
     */
    function payProfit(uint optionID)
        internal
        returns (uint profitUnderlying, uint profitUSD)
    {
        Option memory option = options[optionID];
        (, int latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 currentPrice = uint256(latestPrice);
        uint256 underlyingAmount = 0;
        uint256 differ = 0;
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
        pool.send(uint8(option.optionType), optionID, option.holder, profitUnderlying, profitUSD / DECIMAL_RATIO, currentPrice);
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
