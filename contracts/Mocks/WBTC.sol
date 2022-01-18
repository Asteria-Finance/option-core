// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

contract WBTC is ERC20PresetMinterPauser {
  constructor()
    public
    ERC20PresetMinterPauser("Mock WBTC", "WBTC")
    {
        _setupDecimals(8);
        _mint(_msgSender(), 10000000000000 * 10**uint(super.decimals()));
  }
}
