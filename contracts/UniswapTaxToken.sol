// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

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

interface IUniswapV2Pair {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

abstract contract UniswapTaxToken is ERC20, ERC20Burnable, Ownable { //}ERC20Burnable, ERC20Permit, Ownable {
    uint public tax;
    address public taxWallet;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public uniswapV2Pair;

    mapping(address => bool) private isExcludedFromFees;
    mapping(address => bool) public automatedMarketMakerPairs;

    bool private swapping;
    bool public isLiquidityAdded = false;

    constructor(address uniswapAddress, uint taxAmount)
//        ERC20("UniV2", "UNIV2")
//        ERC20Permit("UniV2")
    {
        uniswapV2Router = IUniswapV2Router02(
            uniswapAddress //Uniswap V2 Router
        );

        excludeFromFees(msg.sender, true);
        excludeFromFees(address(this), true);

        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());

        taxWallet = msg.sender;
        tax = taxAmount;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = isLiquidityAdded && (contractTokenBalance >= swapTokensAtAmount());

        if (
            canSwap &&
            !swapping &&
            automatedMarketMakerPairs[to] &&
            !isExcludedFromFees[from] &&
            !isExcludedFromFees[to]
        ) {
            swapping = true;
            swapTokensForEth(Math.min(contractTokenBalance, getExchangeRate()));
            swapping = false;
        }

        bool takeFee = (tax > 0) && !swapping;

        // If any account belongs to _isExcludedFromFee account then remove the fee
        if (isExcludedFromFees[from] || isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        // Only take fees on buys/sells, do not take on wallet transfers
        if (takeFee && (automatedMarketMakerPairs[to] || automatedMarketMakerPairs[from])) {
            fees = (amount * tax) / 1000;
        }

        if (fees > 0) {
            super._transfer(from, address(this), fees);
            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function setTaxWallet(address newWallet) public onlyOwner {
        taxWallet = newWallet;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        isExcludedFromFees[account] = excluded;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
    }

    function withdrawEth(address toAddr) public onlyOwner {
        (bool success, ) = toAddr.call{
            value: address(this).balance
        } ("");
        require(success);
    }

    function getExchangeRate() public view returns (uint) {
        IUniswapV2Pair uniswapPair = IUniswapV2Pair(uniswapV2Pair);
        (uint reserveA, uint reserveB, ) = uniswapPair.getReserves();

        if (address(this) >= uniswapV2Router.WETH())
            (reserveA, reserveB) = (reserveB, reserveA);

        uint product = reserveA * reserveB;
        uint newTokens = product / (reserveB + 1 ether);

        return reserveA - newTokens;
    }

    function swapTokensAtAmount() public view returns (uint) {
        return getExchangeRate() / 5;
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // Generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // Make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // Accept any amount of ETH; ignore slippage
            path,
            address(taxWallet),
            block.timestamp
        );
    }

    // Function to add initial liquidity to Uniswap
    function addInitialLiquidity(uint256 tokenAmount) public payable {
        require(!isLiquidityAdded, "Liquidity already added, can't add it again");
        require(tokenAmount > 0, "Must add some tokens");
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");
        require(msg.value > 0, "Must send some ETH");

        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());

        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        transfer(address(this), tokenAmount);
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // Add the liquidity
        uniswapV2Router.addLiquidityETH{value: msg.value}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );

        isLiquidityAdded = true;
    }
}
