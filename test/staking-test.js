const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Staking-Test", function () {
  var token;
  var rewardToken;
  var rewardTokenContract;
  var stakingContract;
  var currentReward;
  var acc1;
  var acc2;
  var acc3;
  var acc4;
  before("Contract Deployement", async () => {
    [acc1, acc2, acc3, acc4] = await ethers.getSigners();
    const TokenContract = await ethers.getContractFactory("Token");
    const RewardToken = await ethers.getContractFactory("Token1");
    token = await TokenContract.deploy();
    await token.deployed();
    rewardToken = await RewardToken.deploy();
    await rewardToken.deployed();
    const RewardTokenContract = await ethers.getContractFactory("TokenReward");
    rewardTokenContract = await RewardTokenContract.deploy();
    await rewardTokenContract.deployed();
    const StakingContract = await ethers.getContractFactory("Staking");
    stakingContract = await StakingContract.deploy();
    await stakingContract.deployed();
  });

  it("test that before initialization contract should give error for txn ", async () => {
    await expect(stakingContract.connect(acc2).deposit(ethers.BigNumber.from(10).pow(18).mul(20), 900)).to.be.revertedWith("Not initialized");
  });
  it("Pass initialization perms of staking and it should be as equal as it was given by user", async () => {
    const initializeStaking = await stakingContract.connect(acc1).initialize(token.address, token.address, ethers.BigNumber.from(10).pow(17), 0, 345600, 10, acc1.address);
    await initializeStaking.wait();

    expect(await stakingContract.isInitialized()).to.equal(true);
    expect(await stakingContract.rewardToken()).to.equal(token.address);
    expect(await stakingContract.stakedToken()).to.equal(token.address);
    expect(await stakingContract.startBlock()).to.equal(0);
    expect(await stakingContract.bonusEndBlock()).to.equal(345600);
    expect(await stakingContract.rewardPerBlock()).to.equal(ethers.BigNumber.from(10).pow(17));
    expect(await stakingContract.minLockTime()).to.equal(10);
    expect(await stakingContract.owner()).to.equal(acc1.address);
  });

  it("Pass initialization perms of staking and it should be as equal as it was given by user", async () => {
    const initializeRewardToken = await rewardTokenContract.connect(acc1).initialize(rewardToken.address, ethers.BigNumber.from(10).pow(17), 0, 345600, stakingContract.address, acc1.address);
    await initializeRewardToken.wait();

    expect(await rewardTokenContract.isInitialized()).to.equal(true);
    expect(await rewardTokenContract.rewardToken()).to.equal(rewardToken.address);
    expect(await rewardTokenContract.stakingAddress()).to.equal(stakingContract.address);
    expect(await rewardTokenContract.startBlock()).to.equal(0);
    expect(await rewardTokenContract.bonusEndBlock()).to.equal(345600);
    expect(await rewardTokenContract.rewardPerBlock()).to.equal(ethers.BigNumber.from(10).pow(17));
    expect(await rewardTokenContract.owner()).to.equal(acc1.address);
  });

  it("Token details", async () => {
    console.log(await token.name());
    console.log(await token.symbol());
    console.log(await token.totalSupply());
  });

  it("RewardToken details", async () => {
    console.log(await rewardToken.name());
    console.log(await rewardToken.symbol());
    console.log(await rewardToken.totalSupply());
  });

  it("Token should transfer to users and token balance should be as equal as it was transfered", async () => {
    const amountTransferToUser = await token.transfer(acc2.address, ethers.BigNumber.from(10).pow(20));
    await amountTransferToUser.wait();

    const amountTransferTo2ndUser = await token.transfer(acc3.address, ethers.BigNumber.from(10).pow(20));
    await amountTransferTo2ndUser.wait();

    const amountTransferTo3rdUser = await token.transfer(acc4.address, ethers.BigNumber.from(10).pow(20));
    await amountTransferTo3rdUser.wait();

    expect(await token.balanceOf(acc2.address)).to.equal(ethers.BigNumber.from(10).pow(20));

    expect(await token.balanceOf(acc3.address)).to.equal(ethers.BigNumber.from(10).pow(20));

    expect(await token.balanceOf(acc4.address)).to.equal(ethers.BigNumber.from(10).pow(20));

    const amountTransferToStakingContract = await token.transfer(stakingContract.address, ethers.BigNumber.from(10).pow(21));
    await amountTransferToStakingContract.wait();

    const amountTransferToRewardTokenContract = await rewardToken.transfer(rewardTokenContract.address, ethers.BigNumber.from(10).pow(21));
    await amountTransferToRewardTokenContract.wait();
  });

  describe("Test scenario 1: Staking and Harvesting token by user 1", () => {
    describe("Staking", () => {
      before("Triggering deposite function", async () => {
        await token.connect(acc2).approve(stakingContract.address, ethers.BigNumber.from(2).pow(256).sub(1));

        const stakeAmount = await stakingContract.connect(acc2).deposit(ethers.BigNumber.from(10).pow(18).mul(20), 86400);
        await stakeAmount.wait();
      });
      it("Check staked amount and locktime should be as equal as it was submited and check remain balance of user, it should be 80 ETH", async () => {
        const userInfoAfterStake = await stakingContract.connect(acc2).userInfo(acc2.address);

        expect(userInfoAfterStake[0]).to.equal(ethers.BigNumber.from(10).pow(18).mul(20));

        expect(userInfoAfterStake[5]).to.equal(86400);

        expect(await token.balanceOf(acc2.address)).to.equal(ethers.BigNumber.from(10).pow(18).mul(80));
      });
    });

    describe("Harvesting", () => {
      before("Triggering harvesting function", async () => {
        function timeout(ms) {
          return new Promise((resolve) => setTimeout(resolve, ms));
        }

        await timeout(3000).then(async () => {
          const harvesting = await rewardTokenContract.connect(acc2).claim();
          await harvesting.wait();
        });
      });
      it("Test that pending reward amount should be reflect in user balance", async () => {
        expect(await rewardToken.balanceOf(acc2.address)).to.be.above(ethers.BigNumber.from(10).pow(18).mul(0));
      });
    });

    describe("Test Error genration", () => {
      it("Test should give error for passing value of lock time is less than or equal to previous locked time", async () => {
        await expect(stakingContract.connect(acc2).deposit(ethers.BigNumber.from(10).pow(18).mul(20), 900)).to.be.revertedWith("Locktime must be greater than or equal to previous lock time");
      });
    });
  });

  describe("Test scenario 2: Staking and Harvesting token by user 2 ", () => {
    describe("Staking", () => {
      before("Triggering deposite function", async () => {
        await token.connect(acc3).approve(stakingContract.address, ethers.BigNumber.from(2).pow(256).sub(1));

        const stakeAmount = await stakingContract.connect(acc3).deposit(ethers.BigNumber.from(10).pow(18).mul(20), 86400);
        await stakeAmount.wait();
      });
      it("Check staked amount and locktime should be as equal as it was submited and check remain balance of user, it should be 80 ETH", async () => {
        const userInfoAfterStake = await stakingContract.userInfo(acc3.address);

        expect(userInfoAfterStake[0]).to.equal(ethers.BigNumber.from(10).pow(18).mul(20));

        expect(userInfoAfterStake[5]).to.equal(86400);

        expect(await token.balanceOf(acc3.address)).to.equal(ethers.BigNumber.from(10).pow(18).mul(80));
      });
    });

    describe("Harvesting", () => {
      before("Triggering harvesting function", async () => {
        function timeout(ms) {
          return new Promise((resolve) => setTimeout(resolve, ms));
        }

        await timeout(3000).then(async () => {
          const harvesting = await rewardTokenContract.connect(acc3).claim();
          await harvesting.wait();
        });
      });
      it("Test that pending reward amount should be reflect in user balance", async () => {
        expect(await rewardToken.balanceOf(acc3.address)).to.be.above(ethers.BigNumber.from(10).pow(18).mul(0));
      });
    });
    describe("Test Error genration", () => {
      it("Test should give error for passing value of lock time is less than or equal to previous locked time", async () => {
        await expect(stakingContract.connect(acc3).deposit(ethers.BigNumber.from(10).pow(18).mul(20), 900)).to.be.revertedWith("Locktime must be greater than or equal to previous lock time");
      });
    });
  });

  describe("Test scenario 3: Staking,Harvesting and Unstake token by user 3 ", () => {
    describe("Staking", () => {
      before("Triggering deposite function", async () => {
        await token.connect(acc4).approve(stakingContract.address, ethers.BigNumber.from(2).pow(256).sub(1));

        const stakeAmount = await stakingContract.connect(acc4).deposit(ethers.BigNumber.from(10).pow(18).mul(20), 20);
        await stakeAmount.wait();
      });
      it("Check staked amount and locktime should be as equal as it was submited and check remain balance of user, it should be 80 ETH", async () => {
        const userInfoAfterStake = await stakingContract.userInfo(acc4.address);

        expect(userInfoAfterStake[0]).to.equal(ethers.BigNumber.from(10).pow(18).mul(20));

        expect(userInfoAfterStake[5]).to.equal(20);

        expect(await token.balanceOf(acc4.address)).to.equal(ethers.BigNumber.from(10).pow(18).mul(80));
      });
    });

    describe("Harvesting", () => {
      before("Triggering harvesting function", async () => {
        function timeout(ms) {
          return new Promise((resolve) => setTimeout(resolve, ms));
        }

        await timeout(3000).then(async () => {
          const harvesting = await rewardTokenContract.connect(acc4).claim();
          await harvesting.wait();
        });
      });
      it("Test that pending reward amount should be reflect in user balance", async () => {
        expect(await rewardToken.balanceOf(acc4.address)).to.be.above(ethers.BigNumber.from(10).pow(18).mul(0));
      });
    });

    describe("Test Error genration", () => {
      it("Test should give error for unstaking token before lock time end", async () => {
        await expect(stakingContract.connect(acc4).withdraw(ethers.BigNumber.from(10).pow(18).mul(20))).to.be.revertedWith("You cannot withdraw");
      });
    });

    describe("Unstake", () => {
      before("Triggering unstake function", async () => {
        function timeout(ms) {
          return new Promise((resolve) => setTimeout(resolve, ms));
        }
        await timeout(20000).then(async () => {
          const Unstake = await stakingContract.connect(acc4).withdraw(ethers.BigNumber.from(10).pow(18).mul(20));
          await Unstake.wait();
        });
      });
      it("Test that staked amount should be zero ", async () => {
        const userInfo = await stakingContract.userInfo(acc4.address);
        expect(userInfo[0]).to.equal(0);
      });
    });
  });
  describe("Test scenario 4: update Reward per block", () => {
    before("Triggering updateRewardPerBlock function", async () => {
      const UpdateRewardPerBlock = await stakingContract.connect(acc1).updateRewardPerBlock(ethers.BigNumber.from(10).pow(17).mul(2));
      await UpdateRewardPerBlock.wait();
    });
    it("Test that RewardPerBlock amount should be 0.2ETH ", async () => {
      expect(await stakingContract.rewardPerBlock()).to.equal(ethers.BigNumber.from(10).pow(17).mul(2));
    });
  });
  describe("Test scenario 5: set Lock Disable and deposit amount by user acc2", () => {
    before("Triggering setLockDisable function", async () => {
      const SetLockDisable = await stakingContract.connect(acc1).setLockDisable();
      await SetLockDisable.wait();
    });
    it("Test that lock should be enable and user can deposite amount for less than min time period ", async () => {
      expect(await stakingContract.isLockEnable()).to.equal(false);
      const deposite = await stakingContract.connect(acc2).deposit(ethers.BigNumber.from(10).pow(18).mul(10), 5);
      await deposite.wait();
    });
  });
  describe("Test scenario 6: set reward enable to disable", () => {
    before("Triggering stopReward function", async () => {
      const SetStopReward = await stakingContract.connect(acc1).stopReward();
      await SetStopReward.wait();
      currentReward = await stakingContract.connect(acc2).pendingReward(acc2.address);
      console.log("currentReward: ", currentReward);
    });
    it("Test that pending reward should not be upate after stopping reward ", async () => {
      function timeout(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
      }
      await timeout(4000).then(async () => {
        expect(await stakingContract.connect(acc2).pendingReward(acc2.address)).to.equal(currentReward);
      });
    });
  });
  describe("Test scenario 7: update start and end block", () => {
    before("Triggering updateStartAndEndBlocks function", async () => {
      const updateblocks = await stakingContract.connect(acc1).updateStartAndEndBlocks(5, 3456);
      await updateblocks.wait();
    });
    it("Test that update block should be 5 and 3456 ", async () => {
      expect(await stakingContract.startBlock()).to.equal(5);
      expect(await stakingContract.bonusEndBlock()).to.equal(3456);
    });
  });
  describe("Test scenario 8: update Min Lock Time", () => {
    before("Triggering setMinLockTime function", async () => {
      const updateMinLockTime = await stakingContract.connect(acc1).setMinLockTime(8);
      await updateMinLockTime.wait();
    });
    it("Test that update block should be 5 and 3456 ", async () => {
      expect(await stakingContract.minLockTime()).to.equal(8);
    });
  });
  describe("Test scenario 9: update Min Lock Time", () => {
    before("Triggering setMinLockTime function", async () => {
      const updateMinLockTime = await stakingContract.connect(acc1).setMinLockTime(8);
      await updateMinLockTime.wait();
    });
    it("Test that update block should be 5 and 3456 ", async () => {
      expect(await stakingContract.minLockTime()).to.equal(8);
    });
  });
  describe("Test scenario 10: update Pool End Time", () => {
    before("Triggering setPoolEndTime function", async () => {
      const updatePoolEndTime = await stakingContract.connect(acc1).setPoolEndTime(86400 * 2);
      await updatePoolEndTime.wait();
    });
    it("Test that update pool end time should be 2 days", async () => {
      expect(await stakingContract.poolEndTime()).to.equal(86400 * 2);
    });
  });
  describe("Test scenario 11: update Total Lock Time", () => {
    before("Triggering setTotalLockTime function", async () => {
      const updateTotalLockTime = await stakingContract.connect(acc1).setTotalLockTime(86400 * 3);
      await updateTotalLockTime.wait();
    });
    it("Test that update total lock time should be 3 days", async () => {
      expect(await stakingContract.totalLockTime()).to.equal(86400 * 3);
    });
  });
  describe("Test scenario 12: Transfer ownership", () => {
    before("Triggering setTotalLockTime function", async () => {
      const updateOwner = await stakingContract.connect(acc1).transferOwnership(acc2.address);
      await updateOwner.wait();
    });
    it("Test that owner should be acc2", async () => {
      expect(await stakingContract.owner()).to.equal(acc2.address);
    });
  });
  describe("Test scenario 13: Transfer ownership", () => {
    before("Triggering setTotalLockTime function", async () => {
      const updateOwner = await stakingContract.connect(acc2).transferOwnership(acc3.address);
      await updateOwner.wait();
    });
    it("Test that owner should be acc2", async () => {
      expect(await stakingContract.owner()).to.equal(acc3.address);
    });
  });
});
