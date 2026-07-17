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

/**
 * @dev Minimal ERC20 interface for staking and reward token interactions.
 */
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract BindowsStaking {
    // IERC20 token contract instance
    IERC20 public stakingToken;
    address public tokenAddress;
    address public devAddress;
    
    // Constant fee configuration
    uint256 public constant DEV_FEE_BPS = 500; // 5% (500 basis points)
    uint256 public constant BPS_DIVISOR = 10000;

    // Staking tracking variables
    uint256 public totalStaked;
    
    // Reward distribution variables (Synthetix-style algorithm)
    uint256 public rewardPerTokenStored;
    uint256 public lastKnownContractBalance;

    struct UserInfo {
        uint256 stakedBalance;         // Active staked amount
        uint256 rewardPerTokenPaid;    // Snapshotted reward ratio
        uint256 rewardsAccumulated;    // Pending rewards accrued but not yet claimed
    }

    mapping(address => UserInfo) public userInfo;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 rewardAmount, uint256 devFee);
    event TokenAddressConfigured(address indexed newTokenAddress);

    modifier onlyDev() {
        require(msg.sender == devAddress, "Only developer can call this function");
        _;
    }

    // Reentrancy Guard protection
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

    /**
     * @notice Allows the developer to set the ERC20 token address after deployment.
     * @param _tokenAddress The address of the BEP20/ERC20 token.
     */
    function setTokenAddress(address _tokenAddress) external onlyDev {
        require(tokenAddress == address(0), "Token address is already initialized");
        require(_tokenAddress != address(0), "Invalid token address");
        stakingToken = IERC20(_tokenAddress);
        tokenAddress = _tokenAddress;
        emit TokenAddressConfigured(_tokenAddress);
    }

    /**
     * @notice Dynamically calculates and updates the rewards tracking logic before any state changes.
     * @dev Automatically triggers on deposit, withdrawal, and claim.
     */
    modifier updateReward(address account) {
        // Sync any external rewards (incoming transfers) before modifying the states
        _syncRewards();
        
        if (account != address(0)) {
            userInfo[account].rewardsAccumulated = pendingRewards(account);
            userInfo[account].rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    /**
     * @notice Internal function to calculate external incoming rewards.
     * @dev Detects any increase in the contract balance that is not related to users deposits.
     */
    function _syncRewards() internal {
        if (tokenAddress == address(0)) return;

        uint256 currentBalance = stakingToken.balanceOf(address(this));
        
        // If current balance is greater than what we recorded (deposits + old reward pool),
        // the excess amount is distributed as new rewards.
        if (currentBalance > lastKnownContractBalance) {
            uint256 newRewards = currentBalance - lastKnownContractBalance;
            
            if (totalStaked > 0) {
                rewardPerTokenStored += (newRewards * 1e18) / totalStaked;
            }
            
            // Update historical record
            lastKnownContractBalance = currentBalance;
        }
    }

    /**
     * @notice Calculates the current pending rewards of a specific user in real-time.
     */
    function pendingRewards(address account) public view returns (uint256) {
        if (totalStaked == 0) {
            return userInfo[account].rewardsAccumulated;
        }
        
        // Compute virtual update if some transfers occurred without updateReward calling first
        uint256 currentBalance = stakingToken.balanceOf(address(this));
        uint256 virtualRewardPerToken = rewardPerTokenStored;
        
        if (currentBalance > lastKnownContractBalance) {
            uint256 newRewards = currentBalance - lastKnownContractBalance;
            virtualRewardPerToken += (newRewards * 1e18) / totalStaked;
        }

        UserInfo memory user = userInfo[account];
        return ((user.stakedBalance * (virtualRewardPerToken - user.rewardPerTokenPaid)) / 1e18) + user.rewardsAccumulated;
    }

    /**
     * @notice Returns the user's ratio (pool share percentage) in basis points (10000 = 100%).
     */
    function getUserPoolRatio(address account) external view returns (uint256) {
        if (totalStaked == 0) return 0;
        return (userInfo[account].stakedBalance * BPS_DIVISOR) / totalStaked;
    }

    /**
     * @notice Stake tokens into the pool.
     */
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(tokenAddress != address(0), "Token address not set");
        require(amount > 0, "Cannot stake 0");

        // Dynamic protection: safely transfer tokens from user to contract
        uint256 balanceBefore = stakingToken.balanceOf(address(this));
        bool success = stakingToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Staking transfer failed");
        uint256 actualStakedAmount = stakingToken.balanceOf(address(this)) - balanceBefore;

        userInfo[msg.sender].stakedBalance += actualStakedAmount;
        totalStaked += actualStakedAmount;
        
        // Update bookkeeping
        lastKnownContractBalance = stakingToken.balanceOf(address(this));

        emit Staked(msg.sender, actualStakedAmount);
    }

    /**
     * @notice Withdraw active staked tokens and claims pending rewards automatically.
     * @dev Double-spend is native protected by checking user's balance and deducting before any external transfer.
     */
    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(userInfo[msg.sender].stakedBalance >= amount, "Withdrawal amount exceeds staked balance");

        // Safely claim pending rewards first (to apply tax)
        _claimReward(msg.sender);

        // Deduct balance from user BEFORE transferring to prevent double-spending
        userInfo[msg.sender].stakedBalance -= amount;
        totalStaked -= amount;

        bool success = stakingToken.transfer(msg.sender, amount);
        require(success, "Withdrawal transfer failed");

        // Update bookkeeping
        lastKnownContractBalance = stakingToken.balanceOf(address(this));

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Claims only the accrued rewards without unstaking active tokens.
     */
    function claimReward() external nonReentrant updateReward(msg.sender) {
        _claimReward(msg.sender);
    }

    /**
     * @dev Internal handling of claiming rewards and deducting fees.
     */
    function _claimReward(address account) internal {
        uint256 reward = userInfo[account].rewardsAccumulated;
        if (reward > 0) {
            userInfo[account].rewardsAccumulated = 0;

            // Compute 5% dev fee
            uint256 devFee = (reward * DEV_FEE_BPS) / BPS_DIVISOR;
            uint256 userAmount = reward - devFee;

            // Transfer dev fee to developer address
            if (devFee > 0) {
                bool successDev = stakingToken.transfer(devAddress, devFee);
                require(successDev, "Dev fee transfer failed");
            }

            // Transfer remaining 95% rewards to user
            bool successUser = stakingToken.transfer(account, userAmount);
            require(successUser, "Reward transfer failed");

            // Update bookkeeping
            lastKnownContractBalance = stakingToken.balanceOf(address(this));

            emit RewardClaimed(account, userAmount, devFee);
        }
    }
}
