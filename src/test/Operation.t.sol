// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_operation_lowerThanThreshold(uint256 _amount) public {
        vm.assume(
            _amount > minFuzzAmount && _amount < strategy.depositThreshold()
        );

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // threshold hasnt been met so should be idle
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_operation_greaterThanThreshold(uint256 _amount) public {
        vm.assume(
            _amount > strategy.depositThreshold() && _amount < maxFuzzAmount
        );

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // thresholds been met so shouldnt be idle
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_deposits_afterMoreThanThreshold(uint256 _amount) public {
        vm.assume(
            _amount > minFuzzAmount && _amount < strategy.depositThreshold()
        );

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // threshold hasnt been met so should be idle
        checkStrategyTotals(strategy, _amount, 0, _amount);

        assertEq(strategy.thresholdMet(), false);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, strategy.depositThreshold());

        // thresholds now been met so should be debt
        uint256 total = _amount + strategy.depositThreshold();
        checkStrategyTotals(strategy, total, total, 0);

        assertEq(strategy.thresholdMet(), true);

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(total, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + total,
            "!final balance"
        );
    }

    function test_withdraw_locked(uint256 _amount) public {
        vm.assume(
            _amount > strategy.depositThreshold() && _amount < maxFuzzAmount
        );

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // thresholds been met so should be debt
        checkStrategyTotals(strategy, _amount, _amount, 0);

        vm.prank(management);
        strategy.setTimeToUnlock(block.timestamp + 1e6);

        assertEq(strategy.availableWithdrawLimit(user), 0, "limit");
        assertEq(strategy.maxRedeem(user), 0, "redeem");
        assertEq(strategy.maxWithdraw(user), 0, "withdraw");

        vm.expectRevert("ERC4626: withdraw more than max");
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Skip the lockup time
        skip(1e6 + 1);

        // should now be liquid
        assertEq(
            strategy.availableWithdrawLimit(user),
            asset.balanceOf(0x3835a58CA93Cdb5f912519ad366826aC9a752510),
            "limit"
        );
        assertEq(strategy.maxRedeem(user), _amount, "redeem");
        assertEq(strategy.maxWithdraw(user), _amount, "withdraw");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 1, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_setters(address _rando) public {
        uint256 unlocked = strategy.timeToUnlock();
        assertEq(strategy.freezeTimeToUnlock(), false);

        vm.expectRevert("!Authorized");
        vm.prank(_rando);
        strategy.setTimeToUnlock(unlocked + 1);

        vm.expectRevert("!Authorized");
        vm.prank(_rando);
        strategy.freezeUnlock();

        vm.prank(management);
        strategy.freezeUnlock();

        assertEq(strategy.freezeTimeToUnlock(), true);
        assertEq(unlocked, strategy.timeToUnlock());

        vm.expectRevert("lock frozen");
        vm.prank(management);
        strategy.setTimeToUnlock(unlocked + 1);

        assertEq(strategy.freezeTimeToUnlock(), true);
        assertEq(unlocked, strategy.timeToUnlock());
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(
            _amount > strategy.depositThreshold() && _amount < maxFuzzAmount
        );
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(3 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 1, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(
            _amount > strategy.depositThreshold() && _amount < maxFuzzAmount
        );
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(10 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 1, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        assertTrue(!strategy.tendTrigger());

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertTrue(!strategy.tendTrigger());

        // Skip some time
        skip(1 days);

        assertTrue(!strategy.tendTrigger());

        vm.prank(keeper);
        strategy.report();

        assertTrue(!strategy.tendTrigger());

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        assertTrue(!strategy.tendTrigger());

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertTrue(!strategy.tendTrigger());
    }
}
