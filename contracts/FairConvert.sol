// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract FairConvert {
    address public tokenA;
    address public tokenB;

    constructor(address _tokenA, address _tokenB) {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function swap(uint256 amount) public {
        // Directly burn token A by transferring from the sender to address(0)
        require(IERC20(tokenA).transferFrom(msg.sender, address(this), amount), "Receiving token A failed");

        uint256 newAmount = amount * 888 / 1000;

        // Transfer token B from this contract to the sender
        require(IERC20(tokenB).transfer(msg.sender, newAmount), "Transfer of token B failed");
    }
}
