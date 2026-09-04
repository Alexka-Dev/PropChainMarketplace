// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/**
 * @title IRentalEscrow
 * @notice Interfaz para el contrato de custodia de depósitos y cobro de alquileres.
 */
interface IRentalEscrow {
    struct Lease {
        uint256 vaultId;
        address tenant;
        uint256 monthlyRent;
        uint256 securityDeposit;
        uint256 leaseStart;
        uint256 leaseEnd;
        uint256 lastPaymentTimestamp;
        bool isActive;
    }

    event LeaseCreated(
        uint256 indexed leaseId,
        uint256 indexed vaultId,
        address indexed tenant,
        uint256 monthlyRent,
        uint256 securityDeposit,
        uint256 leaseStart,
        uint256 leaseEnd
    );

    event RentPaid(uint256 indexed leaseId, address indexed tenant, uint256 amount, uint256 timestamp);
    event DepositRefunded(uint256 indexed leaseId, address indexed tenant, uint256 amount);
    event LeaseTerminated(uint256 indexed leaseId);

    function createLease(
        uint256 vaultId_,
        address tenant_,
        uint256 monthlyRent_,
        uint256 securityDeposit_,
        uint256 durationInMonths_
    ) external returns (uint256);

    function payRent(uint256 leaseId_) external;

    function getLease(uint256 leaseId_) external view returns (Lease memory);
}