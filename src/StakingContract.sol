// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CloudCommitmentRewards
/// @author
/// @notice Users deposit CLOUD tokens before beginDate.
///         Users that keep their tokens deposited until eligibilityTime
///         receive a proportional share of the reward pool.
///
/// @dev Reward denominator is snapshotted at finalize().
contract CloudCommitmentRewards {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error DepositsClosed();
    error RewardsNotReady();
    error AlreadyFinalized();
    error AlreadyClaimed();
    error NotEligible();
    error ZeroAmount();
    error InsufficientBalance();
    error NothingToWithdraw();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant HOLD_DURATION = 7 days;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IERC20 public immutable cloud;

    uint256 public immutable beginDate;
    uint256 public immutable eligibilityTime;
    uint256 public immutable rewardPool;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    bool public finalized;

    // Total deposits still eligible for rewards
    uint256 public totalEligibleDeposits;

    mapping(address => uint256) public deposits;

    // User permanently loses eligibility if withdrawing early
    mapping(address => bool) public withdrewEarly;

    mapping(address => bool) public rewardClaimed;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited(address indexed user, uint256 amount);

    event Withdrawn(address indexed user, uint256 amount, bool forfeitedRewards);

    event Finalized(uint256 totalEligibleDeposits);

    event RewardClaimed(address indexed user, uint256 reward);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _cloud CLOUD token
    /// @param _beginDate Deposits allowed until this timestamp
    /// @param _rewardPool Amount of CLOUD tokens reserved for rewards
    ///
    /// @dev Deployer must fund:
    ///      rewardPool
    /// before users claim rewards.
    constructor(IERC20 _cloud, uint256 _beginDate, uint256 _rewardPool) {
        if (_beginDate <= block.timestamp) revert DepositsClosed();
        if (_rewardPool == 0) revert ZeroAmount();

        cloud = _cloud;
        beginDate = _beginDate;
        eligibilityTime = _beginDate + HOLD_DURATION;
        rewardPool = _rewardPool;
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 amount) external {
        if (block.timestamp >= beginDate) revert DepositsClosed();
        if (amount == 0) revert ZeroAmount();

        deposits[msg.sender] += amount;

        // Only eligible users count toward rewards
        if (!withdrewEarly[msg.sender]) {
            totalEligibleDeposits += amount;
        }

        cloud.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function withdraw(uint256 amount) external {
        uint256 balance = deposits[msg.sender];

        if (amount == 0) revert ZeroAmount();
        if (amount > balance) revert InsufficientBalance();

        deposits[msg.sender] = balance - amount;

        bool forfeited;

        // Early withdrawal permanently removes eligibility
        if (block.timestamp < eligibilityTime && !withdrewEarly[msg.sender]) {
            withdrewEarly[msg.sender] = true;

            // Remove ALL remaining stake from eligible pool
            totalEligibleDeposits -= balance;

            forfeited = true;
        } else if (!withdrewEarly[msg.sender]) {
            // Normal post-lock withdrawal
            totalEligibleDeposits -= amount;
        }

        cloud.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, forfeited);
    }

    /*//////////////////////////////////////////////////////////////
                                FINALIZE
    //////////////////////////////////////////////////////////////*/

    function finalize() external {
        if (block.timestamp < eligibilityTime) revert RewardsNotReady();

        if (finalized) revert AlreadyFinalized();

        finalized = true;

        emit Finalized(totalEligibleDeposits);
    }

    /*//////////////////////////////////////////////////////////////
                              CLAIM REWARD
    //////////////////////////////////////////////////////////////*/

    function claimReward() external {
        if (!finalized) revert RewardsNotReady();

        if (rewardClaimed[msg.sender]) revert AlreadyClaimed();

        if (withdrewEarly[msg.sender]) revert NotEligible();

        uint256 userDeposit = deposits[msg.sender];

        if (userDeposit == 0) revert NotEligible();

        rewardClaimed[msg.sender] = true;

        uint256 reward = (rewardPool * userDeposit) / totalEligibleDeposits;

        cloud.safeTransfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW
    //////////////////////////////////////////////////////////////*/

    function previewReward(address user) external view returns (uint256) {
        if (withdrewEarly[user] || deposits[user] == 0 || totalEligibleDeposits == 0) {
            return 0;
        }

        return (rewardPool * deposits[user]) / totalEligibleDeposits;
    }
}
