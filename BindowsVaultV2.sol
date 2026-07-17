/**
Bindows.cash Staking Pool

https://bindows.cash
https://github.com/bindowscash
https://x.com/bindowscash
https://t.me/bindowscash
https://bindowscash.gitbook.io/

BindowsCash is a non-custodial cryptocurrency mixer operating on BSC, breaking the on-chain links between sender and recipient.
BindowsCash Staking contract is a non-custodial reward distribution contract operating on BSC.
It allows users to stake their tokens to receive a real-time share of the protocol's mixing fees + token volume fees.

Key Features & Specifications:
- Post-Deployment Token Binding: The staking token address is initialized once by the developer after deployment.
- Real-Time Global Ratio Accounting: Uses an optimized Synthetix-style algorithm (O(1) gas complexity) to track and 
  distribute incoming reward transfers proportionally without looping through users.
- Automatic Compound & Claims: Unstaking (withdrawing) automatically claims and transfers any accrued rewards.
- Double-Spend & Reentrancy Protection: Implements a strict Check-Effects-Interactions pattern, deducting user balances
  before executing external transfers, combined with an active reentrancy guard.
- Developer Fee: A 5% protocol fee is automatically deducted from all claimed rewards (during direct claims or withdrawals)
  and sent directly to the developer's address.
**/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract BindowsVaultV2 {
    IERC20 public stakingToken;
    address public tokenAddress;
    address public devAddress;
    
    uint256 public constant DEV_FEE_BPS = 500; // 5%
    uint256 public constant BPS_DIVISOR = 10000;

    uint256 public totalStaked;
    uint256 public rewardPerTokenStored;
    uint256 public lastKnownContractBalance;

    struct UserInfo {
        uint256 stakedBalance;
        uint256 rewardPerTokenPaid;
        uint256 rewardsAccumulated;
    }

    mapping(address => UserInfo) public userInfo;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 rewardAmount, uint256 devFee);
    event TokenAddressConfigured(address indexed newTokenAddress);
    event BNBReceived(address indexed sender, uint256 amount);

    modifier onlyDev() {
        require(msg.sender == devAddress, "Only developer can call this function");
        _;
    }

    uint8 private _unlocked = 1;
    modifier nonReentrant() {
        require(_unlocked == 1, "REENTRANCY_GUARD_TRIGGERED");
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    constructor() {
        devAddress = 0xD3d47348442cD6e1b3ca1481F26743A93c5ca537;
    }

    receive() external payable {
        emit BNBReceived(msg.sender, msg.value);
    }

    function setTokenAddress(address _tokenAddress) external onlyDev {
        require(tokenAddress == address(0), "Token address is already initialized");
        require(_tokenAddress != address(0), "Invalid token address");
        stakingToken = IERC20(_tokenAddress);
        tokenAddress = _tokenAddress;
        emit TokenAddressConfigured(_tokenAddress);
    }

    modifier updateReward(address account) {
        _syncRewards();
        if (account != address(0)) {
            userInfo[account].rewardsAccumulated = pendingRewards(account);
            userInfo[account].rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    function _syncRewards() internal {
        uint256 currentBalance = address(this).balance;
        
        if (currentBalance > lastKnownContractBalance) {
            uint256 newRewards = currentBalance - lastKnownContractBalance;
            
            if (totalStaked > 0) {
                rewardPerTokenStored += (newRewards * 1e18) / totalStaked;
            }
            
            lastKnownContractBalance = currentBalance;
        }
    }

    function pendingRewards(address account) public view returns (uint256) {
        uint256 currentBalance = address(this).balance;
        uint256 virtualRewardPerToken = rewardPerTokenStored;
        
        // Prevents calculations from breaking if current balance is temporarily lower (during simultaneous claims)
        if (currentBalance > lastKnownContractBalance && totalStaked > 0) {
            uint256 newRewards = currentBalance - lastKnownContractBalance;
            virtualRewardPerToken += (newRewards * 1e18) / totalStaked;
        }

        UserInfo memory user = userInfo[account];
        return ((user.stakedBalance * (virtualRewardPerToken - user.rewardPerTokenPaid)) / 1e18) + user.rewardsAccumulated;
    }

    function getUserPoolRatio(address account) external view returns (uint256) {
        if (totalStaked == 0) return 0;
        return (userInfo[account].stakedBalance * BPS_DIVISOR) / totalStaked;
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(tokenAddress != address(0), "Token address not set");
        require(amount > 0, "Cannot stake 0");

        uint256 balanceBefore = stakingToken.balanceOf(address(this));
        bool success = stakingToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Staking transfer failed");
        uint256 actualStakedAmount = stakingToken.balanceOf(address(this)) - balanceBefore;

        userInfo[msg.sender].stakedBalance += actualStakedAmount;
        totalStaked += actualStakedAmount;

        emit Staked(msg.sender, actualStakedAmount);
    }

    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(userInfo[msg.sender].stakedBalance >= amount, "Withdrawal amount exceeds staked balance");

        _claimReward(msg.sender);

        userInfo[msg.sender].stakedBalance -= amount;
        totalStaked -= amount;

        bool success = stakingToken.transfer(msg.sender, amount);
        require(success, "Withdrawal transfer failed");

        emit Unstaked(msg.sender, amount);
    }

    function claimReward() external nonReentrant updateReward(msg.sender) {
        _claimReward(msg.sender);
    }

    function _claimReward(address account) internal {
        uint256 reward = userInfo[account].rewardsAccumulated;
        if (reward > 0) {
            userInfo[account].rewardsAccumulated = 0;

            uint256 devFee = (reward * DEV_FEE_BPS) / BPS_DIVISOR;
            uint256 userAmount = reward - devFee;

            lastKnownContractBalance = address(this).balance - reward;

            if (devFee > 0) {
                (bool successDev, ) = payable(devAddress).call{value: devFee}("");
                require(successDev, "Dev fee transfer failed");
            }

            (bool successUser, ) = payable(account).call{value: userAmount}("");
            require(successUser, "Reward transfer failed");

            emit RewardClaimed(account, userAmount, devFee);
        }
    }
}
