// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV2Router02 {
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
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface ITaxToken {
    function addInitialLiquidity(uint256 tokenAmount) external payable;
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferOwnership(address newOwner) external;
}

contract UniswapFirstBuy is Ownable {
    uint256 public totalEthContributed;
    uint256 public totalTokensBought;

    uint256 public maxContribution = 0.5 ether;
    mapping(address => uint256) public ethContributions;

    ITaxToken public token;

    bool public isOpen = true;
    bool public isLiquidityAdded = false;

    IUniswapV2Router02 public immutable uniswapV2Router;

    event EthContributed(address addr, uint256 amount);

    constructor(address uniswapAddress)
    {
        uniswapV2Router = IUniswapV2Router02(
            uniswapAddress //Uniswap V2 Router
        );
    }

    function setTokenAddress(address addr) public onlyOwner {
        token = ITaxToken(addr);
    }

    function setMaxContribution(uint256 newMax) public onlyOwner {
        maxContribution = newMax;
    }

    function setIsOpen(bool _isOpen) public onlyOwner {
        isOpen = _isOpen;
    }

    function launchToken(uint256 tokenAmount) public payable onlyOwner {
        require(!isLiquidityAdded, "Already launched");
        require(msg.value > 0, "Must send ETH");

        isOpen = false;

        token.transferFrom(msg.sender, address(this), tokenAmount);
        token.approve(address(token), tokenAmount);
        token.addInitialLiquidity{value: msg.value}(tokenAmount);

        if (totalEthContributed > 0)
            buyTokensWithEth(totalEthContributed);

        isLiquidityAdded = true;
    }

    receive() external payable {
        require(isOpen, "Contributions closed now");
        require(msg.value > 0, "Must send ETH");
        require(ethContributions[msg.sender] + msg.value <= maxContribution, "Contribution exceeds limit");

        // TODO: add FAIR holdings check.
        // TODO: also check when launching!

        ethContributions[msg.sender] += msg.value;
        totalEthContributed += msg.value;

        emit EthContributed(msg.sender, msg.value);
    }

    // Function to buy tokens with the ETH pool
    function buyTokensWithEth(uint256 ethAmount) internal {
        require(address(this).balance >= ethAmount, "Insufficient ETH balance");

        // Set up the path to swap ETH for tokens
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(token);

        uint256 initialTokenBalance = token.balanceOf(address(this));

        // Make the swap
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0, // accept any number of Tokens
            path,
            address(this),
            block.timestamp
        );

        // Update the total tokens bought
        totalTokensBought = token.balanceOf(address(this)) - initialTokenBalance;
    }

    // Function for users to withdraw their tokens
    function withdrawTokens() public {
        require(isLiquidityAdded, "Liquidity not yet added");
        uint256 userEthContribution = ethContributions[msg.sender];
        require(userEthContribution > 0, "No ETH contribution");

        uint256 tokenAmount = calculateTokenAmount(msg.sender);
        ethContributions[msg.sender] = 0;
        token.transfer(msg.sender, tokenAmount);
    }

    // Calculate the amount of tokens a user can withdraw
    function calculateTokenAmount(address userAddy) public view returns (uint256) {
        if (totalEthContributed == 0)
            return 0;

        return (ethContributions[userAddy] * totalTokensBought) / totalEthContributed;
    }

    function getCurrentContribution() public view returns (uint256) {
        return ethContributions[msg.sender];
    }

    function setTokenOwner(address newOwner) public onlyOwner {
        token.transferOwnership(newOwner);
    }

    function emergencyWithdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
