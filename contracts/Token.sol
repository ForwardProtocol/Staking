// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract Token is ERC20 {
    constructor() ERC20("FORWARD", "FP") {
        _mint(msg.sender, 7*10000**18);
    }
}