pragma solidity ^0.8.23;

import "./UniswapTaxToken.sol";

/*
 * telegram: https://t.me/OxFair
 * www: https://0xfair.com
 * github: https://github.com/0xFair/contracts
 * twitter: https://twitter.com/0xFair_eth
 */

contract Fair is UniswapTaxToken {
    constructor(address uniswapAddress)
    UniswapTaxToken(uniswapAddress, 50, 888_000_000)
    ERC20("0xFair", "FAIR")
    {
    }
}
