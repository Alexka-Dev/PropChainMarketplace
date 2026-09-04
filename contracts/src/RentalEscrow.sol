// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IComplianceRegistry {
    function isVerified(address account) external view returns (bool);
}

/**
 * @title RentalEscrow
 * @author BytePeak Technology
 * @notice Depósito en garantía y gestor de pagos periódicos para alquileres de propiedades RWA.
 * @dev Sigue el patrón CEI, ReentrancyGuard, control de acceso granular y verificación KYC.
 */
contract RentalEscrow is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------
    // 1. Roles & Constants
    // ---------------------------------------------------------

    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");

    enum AgreementStatus {
        Inactive,
        Active,
        Completed,
        Disputed
    }

    // ---------------------------------------------------------
    // 2. Structs & State Variables
    // ---------------------------------------------------------

    struct LeaseAgreement {
        uint256 propertyId;         // ID de la propiedad / Vault asociado
        address tenant;             // Dirección del inquilino (debe tener KYC)
        address yieldDistributor;   // Contrato receptor de las rentas para los inversores
        uint256 monthlyRent;        // Canon de arrendamiento mensual (en USDC)
        uint256 securityDeposit;     // Depósito de garantía/fianza (en USDC)
        uint256 rentDueTimestamp;   // Fecha límite para el próximo pago
        uint256 leaseEndTimestamp;  // Fecha de finalización del contrato de alquiler
        uint256 totalPaid;          // Total acumulado pagado en el alquiler
        AgreementStatus status;     // Estado del contrato de arrendamiento
    }

    /// @notice Token de pago oficial (USDC con 6 decimales).
    IERC20 public immutable paymentToken;

    /// @notice Registro KYC/AML.
    IComplianceRegistry public complianceRegistry;

    /// @notice Mapeo de leaseId => LeaseAgreement
    mapping(uint256 => LeaseAgreement) public leaseAgreements;

    /// @notice Contador para los IDs de contratos de arrendamiento.
    uint256 public nextLeaseId;

    // ---------------------------------------------------------
    // 3. Events
    // ---------------------------------------------------------

    event LeaseCreated(
        uint256 indexed leaseId,
        uint256 indexed propertyId,
        address indexed tenant,
        uint256 monthlyRent,
        uint256 securityDeposit,
        uint256 leaseEndTimestamp
    );

    event RentPaid(
        uint256 indexed leaseId,
        address indexed tenant,
        uint256 amount,
        uint256 nextDueTimestamp
    );

    event LeaseEnded(uint256 indexed leaseId, address indexed tenant, uint256 depositRefunded);
    event LeaseDisputed(uint256 indexed leaseId, string reason);
    event ComplianceRegistryUpdated(address indexed newRegistry);

    // ---------------------------------------------------------
    // 4. Custom Errors
    // ---------------------------------------------------------

    error ZeroAddressDetected();
    error TenantNotKYCVerified(address tenant);
    error InvalidLeaseDuration();
    error LeaseNotActive();
    error NotTenant();
    error RentNotDueYet();
    error LeasePeriodNotEnded();

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------

    constructor(
        address paymentToken_,
        address complianceRegistry_,
        address admin_
    ) {
        if (paymentToken_ == address(0) || complianceRegistry_ == address(0) || admin_ == address(0)) {
            revert ZeroAddressDetected();
        }

        paymentToken = IERC20(paymentToken_);
        complianceRegistry = IComplianceRegistry(complianceRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ARBITER_ROLE, admin_);
    }

    // ---------------------------------------------------------
    // External Functions (Patrón CEI Compliant)
    // ---------------------------------------------------------

    /**
     * @notice Registra e inicia un contrato de arrendamiento reteniendo la fianza inicial.
     * @param propertyId_ ID de la propiedad/vault.
     * @param tenant_ Dirección del inquilino.
     * @param yieldDistributor_ Contrato donde se transfieren los pagos de renta.
     * @param monthlyRent_ Canon mensual en unidades del token de pago.
     * @param securityDeposit_ Depósito de garantía en unidades del token de pago.
     * @param durationInDays_ Duración total del contrato en días.
     */
    function createLeaseAgreement(
        uint256 propertyId_,
        address tenant_,
        address yieldDistributor_,
        uint256 monthlyRent_,
        uint256 securityDeposit_,
        uint256 durationInDays_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant returns (uint256) {
        // --- CHECKS ---
        if (tenant_ == address(0) || yieldDistributor_ == address(0)) revert ZeroAddressDetected();
        if (!complianceRegistry.isVerified(tenant_)) revert TenantNotKYCVerified(tenant_);
        if (durationInDays_ == 0) revert InvalidLeaseDuration();

        uint256 leaseId = nextLeaseId;
        uint256 leaseEnd = block.timestamp + (durationInDays_ * 1 days);
        uint256 firstDue = block.timestamp + 30 days;

        // --- EFFECTS ---
        unchecked {
            ++nextLeaseId;
        }

        leaseAgreements[leaseId] = LeaseAgreement({
            propertyId: propertyId_,
            tenant: tenant_,
            yieldDistributor: yieldDistributor_,
            monthlyRent: monthlyRent_,
            securityDeposit: securityDeposit_,
            rentDueTimestamp: firstDue,
            leaseEndTimestamp: leaseEnd,
            totalPaid: 0,
            status: AgreementStatus.Active
        });

        // --- INTERACTIONS ---
        // Transfiere el depósito de garantía (fianza) del inquilino a la custodia del contrato Escrow
        if (securityDeposit_ > 0) {
            paymentToken.safeTransferFrom(tenant_, address(this), securityDeposit_);
        }

        emit LeaseCreated(leaseId, propertyId_, tenant_, monthlyRent_, securityDeposit_, leaseEnd);

        return leaseId;
    }

    /**
     * @notice Permite al inquilino pagar su renta mensual.
     * @dev Transfiere los fondos directamente al YieldDistributor asignado.
     * @param leaseId_ ID del arrendamiento.
     */
    function payRent(uint256 leaseId_) external nonReentrant {
        // --- CHECKS ---
        LeaseAgreement storage lease = leaseAgreements[leaseId_];
        if (lease.status != AgreementStatus.Active) revert LeaseNotActive();
        if (msg.sender != lease.tenant) revert NotTenant();

        uint256 rentAmount = lease.monthlyRent;
        address distributor = lease.yieldDistributor;

        // --- EFFECTS ---
        lease.rentDueTimestamp += 30 days;
        lease.totalPaid += rentAmount;

        // --- INTERACTIONS ---
        // Transfiere la renta desde el inquilino directamente al repartidor de dividendos (YieldDistributor)
        paymentToken.safeTransferFrom(msg.sender, distributor, rentAmount);

        emit RentPaid(leaseId_, msg.sender, rentAmount, lease.rentDueTimestamp);
    }

    /**
     * @notice Concluye el arrendamiento y devuelve la fianza al inquilino si no existen disputas.
     * @param leaseId_ ID del contrato a cerrar.
     */
    function endLease(uint256 leaseId_) external nonReentrant {
        // --- CHECKS ---
        LeaseAgreement storage lease = leaseAgreements[leaseId_];
        if (lease.status != AgreementStatus.Active) revert LeaseNotActive();
        if (block.timestamp < lease.leaseEndTimestamp) revert LeasePeriodNotEnded();

        uint256 depositToRefund = lease.securityDeposit;

        // --- EFFECTS ---
        lease.status = AgreementStatus.Completed;
        lease.securityDeposit = 0;

        // --- INTERACTIONS ---
        if (depositToRefund > 0) {
            paymentToken.safeTransfer(lease.tenant, depositToRefund);
        }

        emit LeaseEnded(leaseId_, lease.tenant, depositToRefund);
    }

    /**
     * @notice Permite al árbitro/admin intervenir en caso de daños o disputas en la propiedad.
     */
    function resolveDispute(
        uint256 leaseId_,
        uint256 amountToTenant,
        uint256 amountToDistributor
    ) external onlyRole(ARBITER_ROLE) nonReentrant {
        LeaseAgreement storage lease = leaseAgreements[leaseId_];
        if (lease.status != AgreementStatus.Active) revert LeaseNotActive();

        uint256 totalDeposit = lease.securityDeposit;
        require(amountToTenant + amountToDistributor <= totalDeposit, "Exceeds deposit");

        lease.status = AgreementStatus.Disputed;
        lease.securityDeposit = 0;

        if (amountToTenant > 0) {
            paymentToken.safeTransfer(lease.tenant, amountToTenant);
        }
        if (amountToDistributor > 0) {
            paymentToken.safeTransfer(lease.yieldDistributor, amountToDistributor);
        }

        emit LeaseDisputed(leaseId_, "Resolved by Arbiter");
    }

    /**
     * @notice Actualiza la dirección del registro KYC.
     */
    function setComplianceRegistry(address newRegistry_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRegistry_ == address(0)) revert ZeroAddressDetected();
        complianceRegistry = IComplianceRegistry(newRegistry_);
        emit ComplianceRegistryUpdated(newRegistry_);
    }
}