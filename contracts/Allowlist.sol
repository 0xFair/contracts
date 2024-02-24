// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Allowlist is Ownable {
    mapping(address => bool) private allowlist;
    uint256 public allowlistLimit = 800;
    uint256 public allowlistCount = 0;

    // Token requirements for external users
    struct TokenRequirement {
        address token;
        uint256 minAmount;
    }

    TokenRequirement[] public tokenRequirements;

    event AllowlistItemAdded(address addr);
    event AllowlistItemRemoved(address addr);

    function addToAllowlist(address[] calldata addresses) external onlyOwner {
        // We don't check the limit here because owner can add more than the limit
        for (uint256 i = 0; i < addresses.length; i++) {
            if (!allowlist[addresses[i]]) {
                allowlist[addresses[i]] = true;
                allowlistCount++;
                emit AllowlistItemAdded(addresses[i]);
            }
        }
    }

    function removeFromAllowlist(address addr) external onlyOwner {
        if (allowlist[addr]) {
            allowlist[addr] = false;
            allowlistCount--;
            emit AllowlistItemRemoved(addr);
        }
    }

    function setAllowlistLimit(uint256 limit) external onlyOwner {
        allowlistLimit = limit;
    }

    function setTokenRequirements(address[] calldata tokens, uint256[] calldata minAmounts) external onlyOwner {
        require(tokens.length == minAmounts.length, "Array length mismatch");
        delete tokenRequirements;
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenRequirements.push(TokenRequirement(tokens[i], minAmounts[i]));
        }
    }

    function register() external {
        require(!allowlist[msg.sender], "Already registered");
        require(allowlistCount < allowlistLimit, "Allowlist is full");

        bool hasRequiredToken = false;
        for (uint256 i = 0; i < tokenRequirements.length; i++) {
            if (IERC20(tokenRequirements[i].token).balanceOf(msg.sender) >= tokenRequirements[i].minAmount) {
                hasRequiredToken = true;
                break;
            }
        }
        require(hasRequiredToken, "Does not meet token requirements");

        allowlist[msg.sender] = true;
        emit AllowlistItemAdded(msg.sender);
        allowlistCount++;
    }

    function isOnAllowlist(address addr) public view returns (bool) {
        return allowlist[addr];
    }
}
