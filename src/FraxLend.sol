// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IFraxLend} from "./interfaces/IFraxLend.sol";

contract FraxLend is BaseTokenizedStrategy {
    using SafeERC20 for ERC20;

    IFraxLend public constant pair =
        IFraxLend(0x3835a58CA93Cdb5f912519ad366826aC9a752510);

    uint256 public constant depositThreshold = 500_000e18;
    bool public thresholdMet;

    uint256 public timeToUnlock;
    bool public freezeTimeToUnlock;

    constructor(
        address _asset,
        string memory _name,
        uint256 _timeToUnlock
    ) BaseTokenizedStrategy(_asset, _name) {
        ERC20(_asset).safeApprove(address(pair), type(uint256).max);

        timeToUnlock = _timeToUnlock;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        // We dont deposit until the threshold is met.
        if (thresholdMet) {
            pair.deposit(_amount, address(this));

            // Amount will include all idle funds if not deposited yet.
        } else if (_amount > depositThreshold) {
            thresholdMet = true;
            pair.deposit(_amount, address(this));
        }
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        // Only proccess withdraws if we have unlocked the stratey
        if (block.timestamp >= timeToUnlock) {
            // Update exchance rate for conversion.
            pair.updateExchangeRate();
            pair.redeem(
                pair.toAssetShares(_amount, false),
                address(this),
                address(this)
            );
        } else {
            require(false, "Locked!");
        }
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // Acccrue interest
        pair.updateExchangeRate();
        return
            ERC20(asset).balanceOf(address(this)) +
            pair.toAssetAmount(pair.balanceOf(address(this)), false);
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overriden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwhichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The avialable amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(address _owner)
        public
        view
        override
        returns (uint256)
    {
        if (block.timestamp >= timeToUnlock) {
            return super.availableWithdrawLimit(_owner);
        } else {
            return TokenizedStrategy.totalIdle();
        }
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A seperate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        pair.updateExchangeRate();
        uint256 shares = pair.toAssetShares(_amount, false);
        pair.redeem(shares, address(this), address(this));
    }

    // Management can update the lock rate unless it has been frozen.
    function setTimeToUnlock(uint256 _newTime) external onlyManagement {
        require(!freezeTimeToUnlock, "Unlcok frozen");
        timeToUnlock = _newTime;
    }

    // One way switch to freeze the unlock time.
    function freezeUnlock() external onlyManagement {
        freezeTimeToUnlock = true;
    }
}
