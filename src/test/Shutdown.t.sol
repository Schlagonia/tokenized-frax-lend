pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_shudownCanWithdraw(uint256 _amount) public {
        vm.assume(
            _amount > strategy.depositThreshold() && _amount < maxFuzzAmount
        );
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        checkStrategyTotals(strategy, _amount, _amount, 0);
        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 1, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_emergencyWithdraw(uint256 _amount) public {
        vm.assume(
            _amount > strategy.depositThreshold() && _amount < maxFuzzAmount
        );
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        checkStrategyTotals(strategy, _amount, _amount, 0);
        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 1, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 total = strategy.totalAssets();

        vm.prank(management);
        strategy.emergencyWithdraw(total);

        checkStrategyTotals(strategy, total, 0, total);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }
}
