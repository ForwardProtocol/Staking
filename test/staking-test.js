const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Staking-Test", function () {
  var token;
  var stakingContract;
  var acc1;
  var acc2;
  var acc3;
  var acc4;
  before("Contract Deployement", async () => {
    [acc1, acc2, acc3, acc4] = await ethers.getSigners();
    const TokenContract = await ethers.getContractFactory("Token");
    token = await TokenContract.deploy();
    await token.deployed();
    const StakingContract = await ethers.getContractFactory("Staking");
    stakingContract = await StakingContract.deploy();
    await stakingContract.deployed();
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

  it("Token details", async () => {
    console.log(await token.name());
    console.log(await token.symbol());
    console.log(await token.totalSupply());
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
          const harvesting = await stakingContract.connect(acc2).deposit(0, 86400);
          await harvesting.wait();
        });
      });
      it("Test that pending reward amount should be zero", async () => {
        const pendingRewardAfterHarvest = await stakingContract.pendingReward(acc2.address);

        expect(pendingRewardAfterHarvest).to.equal(0);
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
          const harvesting = await stakingContract.connect(acc3).deposit(0, 86400);
          await harvesting.wait();
        });
      });
      it("Test that pending reward amount should be zero", async () => {
        const pendingRewardAfterHarvest = await stakingContract.pendingReward(acc3.address);
        expect(pendingRewardAfterHarvest).to.equal(0);
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
          const harvesting = await stakingContract.connect(acc4).deposit(0, 86400);
          await harvesting.wait();
        });
      });
      it("Test that pending reward amount should be zero", async () => {
        const pendingRewardAfterHarvest = await stakingContract.pendingReward(acc4.address);

        expect(pendingRewardAfterHarvest).to.equal(0);
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
});
