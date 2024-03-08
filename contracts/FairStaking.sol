// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FairStaking is ReentrancyGuard, Ownable {
    struct User {
        uint256 stakedAmount;
        uint256 stakingTimestamp;
        uint256 paidOutRewards;
        uint lockupPeriod;
    }

    mapping(address => User) public users;

    IERC20 public fairToken;
    uint256 public totalStakedAmount;
    uint256 public totalWeight;

    // Total rewards ever deposited
    uint256 public stakingRewardsTotal;
    // Remaining rewards to be claimed
    uint256 public stakingRewardsRemaining;
    // When we started staking
    uint256 public stakingStartTimestamp;
    uint256 public stakingEndTimestamp;

    uint256 public minLockupPeriod = 7 days;
    uint256 public bonus30Days = 50;
    uint256 public bonus90Days = 100;

    uint public constant LOCKUP_WEEK = 0;
    uint public constant LOCKUP_MONTH = 1;
    uint public constant LOCKUP_QUARTER = 2;

    mapping(uint => uint256) public lockupTimes;
    mapping(uint => uint256) public rewardBonuses;

    uint256 public constant SECONDS_IN_YEAR = 365 days;

    event Staked(address indexed user, uint256 amount, uint lockupPeriod);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardTokensDeposited(address indexed user, uint256 amount);

    constructor(address _fairToken) {
        fairToken = IERC20(_fairToken);

        stakingRewardsRemaining = 0;
        stakingRewardsTotal = 0;

        lockupTimes[LOCKUP_WEEK] = 7 days;
        lockupTimes[LOCKUP_MONTH] = 30 days;
        lockupTimes[LOCKUP_QUARTER] = 90 days;

        rewardBonuses[LOCKUP_WEEK] = 0;
        rewardBonuses[LOCKUP_MONTH] = 50;
        rewardBonuses[LOCKUP_QUARTER] = 100;

        stakingStartTimestamp = block.timestamp;
        stakingEndTimestamp = block.timestamp + SECONDS_IN_YEAR;
    }

    function depositRewardTokens(uint256 _amount) external {
        fairToken.transferFrom(msg.sender, address(this), _amount);
        stakingRewardsTotal += _amount;
        stakingRewardsRemaining += _amount;

        emit RewardTokensDeposited(msg.sender, _amount);
    }

    function stake(uint256 _amount, uint _lockupPeriod) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        require(lockupTimes[_lockupPeriod] > 0, "Invalid lockup period");
        require(_lockupPeriod >= users[msg.sender].lockupPeriod, "Cannot decrease lockup period");

        if (users[msg.sender].stakedAmount > 0) {
            claimRewards();
        }

        fairToken.transferFrom(msg.sender, address(this), _amount);

        // Remove the old weight, since it can change if the user is restaking with a different lockup period.
        totalWeight -= getUserWeight(msg.sender);
        users[msg.sender].stakedAmount += _amount;
        users[msg.sender].lockupPeriod = _lockupPeriod;
        totalWeight += getUserWeight(msg.sender);

        // Resetting staking timestamp and paid out rewards along with it.
        users[msg.sender].stakingTimestamp = block.timestamp;
        users[msg.sender].paidOutRewards = 0;

        totalStakedAmount += _amount;

        emit Staked(msg.sender, _amount, _lockupPeriod);
    }

    function unstake() external nonReentrant {
        require(users[msg.sender].stakedAmount > 0, "No stake to unstake");
        require(block.timestamp >= users[msg.sender].stakingTimestamp + lockupTimes[users[msg.sender].lockupPeriod], "Lockup period not ended");

        claimRewards();

        uint256 amountToUnstake = users[msg.sender].stakedAmount;

        totalWeight -= getUserWeight(msg.sender);
        totalStakedAmount -= amountToUnstake;

        users[msg.sender].stakedAmount = 0;
        users[msg.sender].stakingTimestamp = 0;
        users[msg.sender].lockupPeriod = 0;
        users[msg.sender].paidOutRewards = 0;

        fairToken.transfer(msg.sender, amountToUnstake);

        emit Unstaked(msg.sender, amountToUnstake);
    }

    function claimRewards() public {
        User storage user = users[msg.sender];
        require(user.stakedAmount > 0, "No stake to claim rewards");
        require(stakingEndTimestamp > block.timestamp, "Staking period ended");

        uint256 pendingRewards = calculateRewards(msg.sender);
        if (pendingRewards == 0) {
            return;
        }

        user.paidOutRewards += pendingRewards;
        // Update remaining rewards
        stakingRewardsRemaining -= pendingRewards;

        fairToken.transfer(msg.sender, pendingRewards);

        emit RewardClaimed(msg.sender, pendingRewards);
    }

    function calculateRewards(address _user) public view returns (uint256) {
        User storage user = users[_user];
        if (user.stakedAmount == 0) {
            return 0;
        }

        uint256 userStakingDuration = block.timestamp - user.stakingTimestamp;
        uint256 totalStakingDuration = stakingEndTimestamp - stakingStartTimestamp;
        uint256 userStakingDurationShare = (userStakingDuration * 1e9) / totalStakingDuration;

        uint256 userWeight = getUserWeight(_user);
        uint256 userWeightShare = (userWeight * 1e9) / totalWeight;

        // Rewards can be negative as staking parameters change (i.e. stakingEndTimestamp)
        uint256 accrued = userStakingDurationShare * userWeightShare * stakingRewardsTotal / 1e18;
        if (accrued > user.paidOutRewards)
            return accrued - user.paidOutRewards;
        else
            return 0;
    }

    function getUserWeight(address _user) public view returns (uint256) {
        User storage user = users[_user];
        if (user.stakedAmount == 0) {
            return 0;
        }

        return user.stakedAmount * (100 + rewardBonuses[user.lockupPeriod]);
    }

    function setLockupTime(uint _lockupPeriod, uint256 _period) external onlyOwner {
        lockupTimes[_lockupPeriod] = _period;
    }

    function setRewardBonus(uint _lockupPeriod, uint256 _bonus) external onlyOwner {
        rewardBonuses[_lockupPeriod] = _bonus;
    }

    function setStakingEndTimestamp(uint256 _timestamp) external onlyOwner {
        require(_timestamp > block.timestamp, "End timestamp must be in the future");
        stakingEndTimestamp = _timestamp;
    }

    function currentBaseApy() public view returns (uint256) {
        return apyForRatio(stakingRewardsTotal, totalStakedAmount);
    }

    function getUserApy(address user_address) public view returns (uint256) {
        uint256 userWeight = getUserWeight(user_address);
        uint256 userWeightShare = (userWeight * 1e9) / totalWeight;

        return apyForRatio(
            userWeightShare * stakingRewardsTotal / 1e9,
            users[user_address].stakedAmount
        );
    }

    function apyForRatio(uint256 rewards, uint256 balance) public view returns (uint256) {
        if (balance == 0) {
            return 0;
        }

        return (rewards * 1e9 / balance) *
                (SECONDS_IN_YEAR * 1e9 / (stakingEndTimestamp - stakingStartTimestamp)) / 1e14;
    }
}
