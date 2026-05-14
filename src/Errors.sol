// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Thrown when the caller is not the agent
error NotAgent();

/// @notice Thrown when an zero amount is provided
error ZeroAmount();

/// @notice Thrown when the amount of tokens returned is zero
error ZeroAmountReturn();

/// @notice Thrown when the amount of output returned is insufficient
error InsufficientOutput();

/// @notice Thrown when there is no fee to claim
error NoFeeToClaim();

/// @notice Thrown when the fee rate is invalid
error InvalidFeeRate();

/// @notice Thrown when the pool is complete
error PoolComplete();

/// @notice Thrown when the pool is incomplete
error PoolIncomplete();
