// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Allowlist is Ownable {
    mapping(address => bool) private allowlist;
    uint256 public allowlistCount = 0;

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

    function isOnAllowlist(address addr) public view returns (bool) {
        return allowlist[addr];
    }
}
