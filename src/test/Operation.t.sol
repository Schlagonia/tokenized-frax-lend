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

    function test_profitableReport(uint256 _amount, uint16 _profitFactor)
        public
    {
        vm.assume(
            _amount > strategy.depositThreshold() && _amount < maxFuzzAmount
        );
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
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
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
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
