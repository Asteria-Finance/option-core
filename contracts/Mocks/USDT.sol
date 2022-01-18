// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

contract USDT is ERC20PresetMinterPauser {
  constructor()
    public
    ERC20PresetMinterPauser("Mock USDT", "USDT")
    {
        _setupDecimals(6);
        _mint(_msgSender(), 10000000000000 * 10**uint(super.decimals()));
  }
}
