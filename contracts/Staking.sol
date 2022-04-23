// File: @openzeppelin/contracts/utils/Context.sol

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// File: contracts/Staking.sol

contract Staking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.AddressSet;

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

    // Total amount staked
    uint256 public totalStaked;

    // Min locktime
    uint256 public minLockTime;

    // Max Lock time from pool start 
    uint256 public totalLockTime = 367200 seconds;

    // Pool end Time
    uint256 public poolEndTime;

    // Check lock is enable or not
    bool public isLockEnable;

    // The reward token
    IERC20Metadata public rewardToken;

    // The staked token
    IERC20Metadata public stakedToken;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    // List of users who take part in staking
    EnumerableSet.AddressSet private holders;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 totalEarned; // Total earned reward 
        uint256 totalBonus; // Total bonus earned
        uint256 depositTime; // Deposit time
        uint256 lockTime; //Deposit will be lock for time
    }

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
     * @param _minLockTime: pool minimum Lock time for depositing tokens 
     * @param _admin: admin address with ownership
     */
    function initialize(
        IERC20Metadata _stakedToken,
        IERC20Metadata _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _minLockTime,
        address _admin
    ) external onlyOwner{
        require(!isInitialized, "Already initialized");

        // Make this contract initialized
        isInitialized = true;

        stakedToken = _stakedToken;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        minLockTime = _minLockTime;
        poolEndTime = block.timestamp.add(totalLockTime);

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10**(uint256(30).sub(decimalsRewardToken)));

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        isLockEnable = true;

        // Transfer ownership to the admin address who becomes owner of the contract
        transferOwnership(_admin);
    }

    /*
     * @notice Set lock enable
     */
    function setLockEnable() public onlyOwner{
        isLockEnable = true;
    }

    /*
     * @notice Set lock disable
     */
    function setLockDisable() public onlyOwner{
        isLockEnable = false;
    }

    /*
     * @notice Set Total Lock time
     * @param time: time in seconds
     */
    function setTotalLockTime(uint256 time) public onlyOwner{
        totalLockTime = time;
    }

    /*
     * @notice Set Total Lock time
     * @param time: unix timestamp
     */
    function setPoolEndTime(uint256 time) public onlyOwner{
        poolEndTime = time;
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function deposit(uint256 _amount, uint256 _lockTime) external nonReentrant {
        require(isInitialized, "Not initialized");
        UserInfo storage user = userInfo[msg.sender];

        _updatePool();

        if (user.amount > 0) {
            // uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt).mul(user.lockTime.div(15 minutes).mul(1e4)).div(1e4);
            uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
            if (pending > 0) {
                user.totalEarned = user.totalEarned.add(pending);
                rewardToken.safeTransfer(address(msg.sender), pending);
                uint256 bonus = ((pending.mul(user.lockTime)).div(totalLockTime).mul(1e4)).div(1e4);
                user.totalBonus = user.totalBonus.add(bonus);
                rewardToken.safeTransfer(address(msg.sender), bonus);
            }
        }

        if (_amount > 0) {
            if(isLockEnable){
                if(user.depositTime > 0){
                    uint256 endTime = user.depositTime.add(user.lockTime);
                    if(endTime > block.timestamp){
                        require(_lockTime >= endTime.sub(block.timestamp), "Locktime must be greater than or equal to previous lock time");
                    }
                }
                require(block.timestamp.add(_lockTime) <= poolEndTime, "Please enter valid locktime");
                user.lockTime = _lockTime;
            }
            user.amount = user.amount.add(_amount);
            totalStaked = totalStaked.add(_amount);
            user.depositTime = block.timestamp;
            stakedToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR);

        if (!holders.contains(msg.sender)) {
            require(_lockTime >= minLockTime, "Lock time should not less than minimum locktime");
            holders.add(msg.sender);
        }

        emit Deposit(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if(isLockEnable){
            require(block.timestamp >= user.depositTime.add(user.lockTime), "You cannot withdraw");
        }
        require(user.amount >= _amount, "Amount to withdraw too high");

        _updatePool();

        // uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt).mul(user.lockTime.div(15 minutes).mul(1e4)).div(1e4);
        uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            totalStaked = totalStaked.sub(_amount);
            stakedToken.safeTransfer(address(msg.sender), _amount);
        }

        if (pending > 0) {
            user.totalEarned = user.totalEarned.add(pending);
            rewardToken.safeTransfer(address(msg.sender), pending);
            uint256 bonus = ((pending.mul(user.lockTime)).div(totalLockTime).mul(1e4)).div(1e4);
            user.totalBonus = user.totalBonus.add(bonus);
            rewardToken.safeTransfer(address(msg.sender), bonus);
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR);

        if (holders.contains(msg.sender) && user.amount == 0) {
            holders.remove(msg.sender);
        }

        emit Withdraw(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        if (amountToTransfer > 0) {
            totalStaked = totalStaked.sub(amountToTransfer);
            stakedToken.safeTransfer(address(msg.sender), amountToTransfer);
        }

        if (holders.contains(msg.sender) && user.amount == 0) {
            holders.remove(msg.sender);
        }

        emit EmergencyWithdraw(msg.sender, user.amount);
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
        require(_tokenAddress != address(stakedToken), "Cannot be staked token");
        require(_tokenAddress != address(rewardToken), "Cannot be reward token");

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
     * @notice Set Minimum Lock time
     * @param _minLockTime: time in seconds
     * @dev Only callable by owner
     */
    function setMinLockTime(uint256 _minLockTime) external onlyOwner {
        minLockTime = _minLockTime;
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
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
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
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
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
     * @notice get total number of stakers
     */
    function getNumberOfStakers() public view returns (uint) {
        return holders.length();
    }

    /*
     * @notice get stakers list
     */
    function getStakersList(uint startIndex, uint endIndex) 
        public 
        view 
        returns (address[] memory stakers, 
            uint[] memory stakingTimestamps, 
            uint[] memory stakedTokens,
            uint[] memory lockTime) {
        require (startIndex < endIndex);
        
        uint length = endIndex.sub(startIndex);
        address[] memory _stakers = new address[](length);
        uint[] memory _stakingTimestamps = new uint[](length);
        uint[] memory _stakedTokens = new uint[](length);
        uint[] memory _lockTime = new uint[](length);
        
        for (uint i = startIndex; i < endIndex; i = i.add(1)) {
            address staker = holders.at(i);
            uint listIndex = i.sub(startIndex);
            _stakers[listIndex] = staker;
            _stakingTimestamps[listIndex] = userInfo[staker].depositTime;
            _stakedTokens[listIndex] = userInfo[staker].amount;
            _lockTime[listIndex] = userInfo[staker].lockTime;
        }
        
        return (_stakers, _stakingTimestamps, _stakedTokens, _lockTime);
    }
    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        uint256 stakedTokenSupply = totalStaked;

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
