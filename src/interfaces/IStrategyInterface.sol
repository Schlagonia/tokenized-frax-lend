// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function depositThreshold() external view returns (uint256);

    function thresholdMet() external view returns (bool);

    function timeToUnlock() external view returns (uint256);

    function freezeTimeToUnlock() external view returns (bool);

    function setTimeToUnlock(uint256 _newTime) external;

    function freezeUnlock() external;
}
