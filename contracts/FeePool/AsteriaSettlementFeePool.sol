// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../Interfaces/Interfaces.sol";

contract AsteriaSettlementFeePool is IAsteriaERC20FeePool, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    IERC20 public immutable usdt;

    constructor(ERC20 _usdt) public {
        usdt = _usdt;
    }

    function sendProfit(uint amount) external override {
        usdt.safeTransferFrom(msg.sender, owner(), amount);
    }
}
