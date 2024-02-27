// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FairStaking is Ownable {
    IERC20 public fairToken;

    struct Stake {
        uint256 amount;
        uint256 stakeTime;
    }

    mapping(address => Stake) public stakes;
    uint256 public totalStaked;

    // Tracking for rewards
    mapping(address => mapping(address => uint256)) public userTokenRewardsClaimed;
    mapping(address => uint256) public userEthRewardsClaimed;
    mapping(address => uint256) public tokenDistributions;
    uint256 public totalEthAccrued;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, address token, uint256 tokenAmount);
    event EthRewardClaimed(address indexed user, uint256 ethAmount);
    event EthReceived(address sender, uint256 amount);

    constructor(address _fairToken) {
        fairToken = IERC20(_fairToken);
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake 0");
        fairToken.transferFrom(msg.sender, address(this), amount);
        if (stakes[msg.sender].amount > 0) {
            stakes[msg.sender].amount += amount;
        } else {
            stakes[msg.sender] = Stake(amount, block.timestamp);
        }
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    function withdrawStake(uint256 amount) external {
        require(amount <= stakes[msg.sender].amount, "Insufficient stake");
        require(block.timestamp >= stakes[msg.sender].stakeTime + 7 days, "Cooldown period not met");
        stakes[msg.sender].amount -= amount;
        // reset stake time when withdrawing
        stakes[msg.sender].stakeTime = block.timestamp;
        totalStaked -= amount;
        fairToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards(address token) external {
        require(stakes[msg.sender].amount > 0, "No stake found");

        uint256 tokenReward = calculateTokenRewards(msg.sender, token);
        uint256 ethReward = calculateEthRewards(msg.sender);

        require(tokenReward > 0 || ethReward > 0, "No rewards available");

        if (tokenReward > 0) {
            IERC20(token).transfer(msg.sender, tokenReward);
            userTokenRewardsClaimed[msg.sender][token] += tokenReward;
            emit RewardClaimed(msg.sender, token, tokenReward);
        }

        if (ethReward > 0) {
            payable(msg.sender).transfer(ethReward);
            userEthRewardsClaimed[msg.sender] += ethReward;
            emit EthRewardClaimed(msg.sender, ethReward);
        }
    }

    function calculateEthRewards(address user) public view returns (uint256) {
        uint256 userShare = stakes[user].amount / totalStaked;

        uint256 totalReward = totalEthAccrued * userShare;
        uint256 claimedReward = userEthRewardsClaimed[user];

        return totalReward > claimedReward ? totalReward - claimedReward : 0;
    }

    function calculateTokenRewards(address user, address token) public view returns (uint256) {
        uint256 userShare = stakes[user].amount / totalStaked;

        uint256 totalReward = tokenDistributions[token] * userShare;
        uint256 claimedReward = userTokenRewardsClaimed[user][token];

        return totalReward > claimedReward ? totalReward - claimedReward : 0;
    }

    function distributeTokenRewards(address token, uint256 amount) public onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        tokenDistributions[token] += amount;
    }

    function distributeEthRewards() external payable onlyOwner {
        require(msg.value > 0, "Amount must be greater than 0");
        totalEthAccrued += msg.value;
    }

    // New receive function to accept ETH and track total accrued
    receive() external payable {
        totalEthAccrued += msg.value;
        emit EthReceived(msg.sender, msg.value);
    }
}
