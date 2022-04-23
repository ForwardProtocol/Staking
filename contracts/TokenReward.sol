// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IStaking {

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 totalEarned; // Total earned reward 
        uint256 totalBonus; // Total bonus earned
        uint256 depositTime; // Deposit time
        uint256 lockTime; //Deposit will be lock for time
    }

    function userInfo(address userAddress) external view returns(UserInfo memory userDetails);   

    function stakedToken() external view returns(IERC20);

    function totalStaked() external view returns(uint256);
}

contract TokenReward is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20Metadata;

    // Whether it is initialized
    bool public isInitialized;

    // Accrued token per share
    uint256 public accTokenPerShare;

    // The block number when FORWARD mining ends.
    uint256 public bonusEndBlock;

    // The block number when FORWARD mining starts.
    uint256 public startBlock;

    // The block number of the last pool update
    uint256 public lastRewardBlock;

    // FORWARD tokens created per block.
    uint256 public rewardPerBlock;

    // The precision factor
    uint256 public PRECISION_FACTOR;

    // Max Lock time from pool start 
    uint256 public totalLockTime = 1440 minutes;

    // The reward token
    IERC20Metadata public rewardToken;

    IStaking public stakingAddress;

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event NewRewardPerBlock(uint256 rewardPerBlock);
    event Withdraw(address indexed user, uint256 amount);

    /*
     * @notice Initialize the contract
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerBlock: reward per block (in rewardToken)
     * @param _startBlock: start block
     * @param _bonusEndBlock: end block
     * @param _admin: admin address with ownership
     */
    function initialize(
        IERC20Metadata _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        IStaking _stakingAddress,
        address _admin
    ) external onlyOwner{
        require(!isInitialized, "Already initialized");

        // Make this contract initialized
        isInitialized = true;

        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        stakingAddress = _stakingAddress;

        uint256 decimalsRewardToken = uint256(IERC20Metadata(rewardToken).decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10**(uint256(30).sub(decimalsRewardToken)));

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        // Transfer ownership to the admin address who becomes owner of the contract
        transferOwnership(_admin);
    }

    /*
     * @notice Set Total Lock time
     * @param time: time in seconds
     */
    function setTotalLockTime(uint256 time) public onlyOwner{
        totalLockTime = time;
    }

    /*
     * @notice Collect reward tokens (if any)
     */
    function claim() external {
        IStaking.UserInfo memory user = IStaking(stakingAddress).userInfo(msg.sender);

        _updatePool();

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
            if (pending > 0) {
                user.totalEarned = user.totalEarned.add(pending);
                rewardToken.safeTransfer(address(msg.sender), pending);
                uint256 bonus = ((pending.mul(user.lockTime)).div(totalLockTime).mul(1e4)).div(1e4);
                user.totalBonus = user.totalBonus.add(bonus);
                rewardToken.safeTransfer(address(msg.sender), bonus);
            }
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR);

    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {

        IERC20Metadata(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        bonusEndBlock = block.number;
    }

    /*
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardPerBlock: the reward per block
     */
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        rewardPerBlock = _rewardPerBlock;
        emit NewRewardPerBlock(_rewardPerBlock);
    }

    /**
     * @notice It allows the admin to update start and end blocks
     * @dev This function is only callable by owner.
     * @param _startBlock: the new start block
     * @param _bonusEndBlock: the new end block
     */
    function updateStartAndEndBlocks(uint256 _startBlock, uint256 _bonusEndBlock) external onlyOwner {

        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        emit NewStartAndEndBlocks(_startBlock, _bonusEndBlock);
    }

    /*
     * @notice View function to see pending bonus on frontend.
     * @param _user: user address
     * @return Pending bonus for a given user
     */
    function pendingBonus(address _user) public view returns (uint256) {
        IStaking.UserInfo memory user = stakingAddress.userInfo(_user);
        uint256 stakedTokenSupply = stakingAddress.stakedToken().balanceOf(address(stakingAddress));
        if (block.number > lastRewardBlock && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 forwardReward = multiplier.mul(rewardPerBlock);
            uint256 adjustedTokenPerShare =
                accTokenPerShare.add(forwardReward.mul(PRECISION_FACTOR).div(stakedTokenSupply));
            uint256 pending = user.amount.mul(adjustedTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
            return ((pending.mul(user.lockTime)).div(totalLockTime).mul(1e4)).div(1e4);
        } else {
            uint256 pending =  user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
            return ((pending.mul(user.lockTime)).div(totalLockTime).mul(1e4)).div(1e4);
        }
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) public view returns (uint256) {
        IStaking.UserInfo memory user = stakingAddress.userInfo(_user);
        uint256 stakedTokenSupply = stakingAddress.stakedToken().balanceOf(address(stakingAddress));
        if (block.number > lastRewardBlock && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 forwardReward = multiplier.mul(rewardPerBlock);
            uint256 adjustedTokenPerShare =
                accTokenPerShare.add(forwardReward.mul(PRECISION_FACTOR).div(stakedTokenSupply));
            uint256 pending = user.amount.mul(adjustedTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
            return (pending);
        } else {
            uint256 pending =  user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
            return (pending);
        }
    }

    /*
     * @notice View function to see pending total reward on frontend.
     * @param _user: user address
     * @return Pending total reward for a given user
     */
    function pendingTotalReward(address _user) external view returns (uint256) {
        uint256 pending = pendingReward(_user).add(pendingBonus(_user));
        return pending;
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        uint256 stakedTokenSupply = stakingAddress.totalStaked();

        if (stakedTokenSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 forwardReward = multiplier.mul(rewardPerBlock);
        accTokenPerShare = accTokenPerShare.add(forwardReward.mul(PRECISION_FACTOR).div(stakedTokenSupply));
        lastRewardBlock = block.number;
    }

    /*
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }
}
