// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/**
 * @title IYieldDistributor
 * @notice Interfaz para el distribuidor inmutable de dividendos de alquiler.
 */
interface IYieldDistributor {
    event YieldDeposited(uint256 indexed vaultId, address indexed depositor, uint256 amount);
    event YieldClaimed(uint256 indexed vaultId, address indexed investor, uint256 amount);

    function depositYield(uint256 vaultId, uint256 amount) external;

    function claimYield(uint256 vaultId) external;

    function getPendingYield(uint256 vaultId, address investor) external view returns (uint256);
}