// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IFractionalVault is IERC1155 {
    function vaults(uint256 vaultId)
        external
        view
        returns (
            address propertyContract,
            uint256 propertyTokenId,
            address originalOwner,
            uint256 totalFractions,
            uint256 availableFractions,
            uint256 pricePerFraction,
            bool isActive
        );
}

interface IComplianceRegistry {
    function isVerified(address account) external view returns (bool);
}

/**
 * @title YieldDistributor
 * @author BytePeak Technology
 * @notice Distribuidor inmutable y proporcional de rentas de alquiler para inversores fraccionados.
 * @dev Sigue el patrón CEI, ReentrancyGuard, control de acceso y cálculo acumulativo por cuota.
 */
contract YieldDistributor is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------
    // 1. Roles & Constants
    // ---------------------------------------------------------

    bytes32 public constant ESCROW_ROLE = keccak256("ESCROW_ROLE");

    /// @notice Escala de precisión matemática para evitar pérdidas por redondeo (1e18).
    uint256 private constant PRECISION = 1e18;

    // ---------------------------------------------------------
    // 2. State Variables
    // ---------------------------------------------------------

    /// @notice Token de pago oficial para los dividendos (ej. USDC).
    IERC20 public immutable paymentToken;

    /// @notice Contrato Vault fraccional (ERC-1155).
    IFractionalVault public immutable fractionalVault;

    /// @notice Registro KYC/AML.
    IComplianceRegistry public complianceRegistry;

    /// @notice Acumulado de rendimiento por fracción para cada vaultId: vaultId => accYieldPerShare
    mapping(uint256 => uint256) public accYieldPerShare;

    /// @notice Registro de dividendos reclamados por usuario: vaultId => (user => amountPaid)
    mapping(uint256 => mapping(address => uint256)) public userRewardPaid;

    // ---------------------------------------------------------
    // 3. Events
    // ---------------------------------------------------------

    event YieldDeposited(uint256 indexed vaultId, address indexed depositor, uint256 amount);
    event YieldClaimed(uint256 indexed vaultId, address indexed investor, uint256 amount);
    event ComplianceRegistryUpdated(address indexed newRegistry);

    // ---------------------------------------------------------
    // 4. Custom Errors
    // ---------------------------------------------------------

    error ZeroAddressDetected();
    error ZeroAmount();
    error InvestorNotKYCVerified(address investor);
    error NoYieldAvailable();
    error InvalidVault();

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------

    constructor(address paymentToken_, address fractionalVault_, address complianceRegistry_, address admin_) {
        if (
            paymentToken_ == address(0) || fractionalVault_ == address(0) || complianceRegistry_ == address(0)
                || admin_ == address(0)
        ) {
            revert ZeroAddressDetected();
        }

        paymentToken = IERC20(paymentToken_);
        fractionalVault = IFractionalVault(fractionalVault_);
        complianceRegistry = IComplianceRegistry(complianceRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ESCROW_ROLE, admin_);
    }

    // ---------------------------------------------------------
    // External / Public State-Changing Functions
    // ---------------------------------------------------------

    /**
     * @notice Recibe los fondos de alquiler y actualiza el acumulador por cuota del vault.
     * @param vaultId_ ID del inmueble / Vault fraccionado.
     * @param amount_ Monto total en USDC transferido para distribución.
     */
    function depositYield(uint256 vaultId_, uint256 amount_) external onlyRole(ESCROW_ROLE) nonReentrant {
        // --- CHECKS ---
        if (amount_ == 0) revert ZeroAmount();

        (,,, uint256 totalFractions,,,) = fractionalVault.vaults(vaultId_);
        if (totalFractions == 0) revert InvalidVault();

        // --- EFFECTS ---
        // Incrementa la renta acumulada por cada token emitiendo la cuota justa
        accYieldPerShare[vaultId_] += (amount_ * PRECISION) / totalFractions;

        // --- INTERACTIONS ---
        paymentToken.safeTransferFrom(msg.sender, address(this), amount_);

        emit YieldDeposited(vaultId_, msg.sender, amount_);
    }

    /**
     * @notice Permite a cualquier inversor con fracciones ERC-1155 reclamar sus dividendos de la propiedad.
     * @param vaultId_ ID del Vault del cual desea cobrar las rentas acumuladas.
     */
    function claimYield(uint256 vaultId_) external nonReentrant {
        // --- CHECKS ---
        if (!complianceRegistry.isVerified(msg.sender)) revert InvestorNotKYCVerified(msg.sender);

        uint256 pending = getPendingYield(vaultId_, msg.sender);
        if (pending == 0) revert NoYieldAvailable();

        // --- EFFECTS ---
        // Se actualiza el registro de lo que el usuario ha cobrado hasta la fecha
        uint256 userBalance = fractionalVault.balanceOf(msg.sender, vaultId_);
        userRewardPaid[vaultId_][msg.sender] = (userBalance * accYieldPerShare[vaultId_]) / PRECISION;

        // --- INTERACTIONS ---
        paymentToken.safeTransfer(msg.sender, pending);

        emit YieldClaimed(vaultId_, msg.sender, pending);
    }

    /**
     * @notice Permite actualizar el contrato KYC en caso de migración.
     */
    function setComplianceRegistry(address newRegistry_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRegistry_ == address(0)) revert ZeroAddressDetected();
        complianceRegistry = IComplianceRegistry(newRegistry_);
        emit ComplianceRegistryUpdated(newRegistry_);
    }

    // ---------------------------------------------------------
    // Public View Functions
    // ---------------------------------------------------------

    /**
     * @notice Calcula en tiempo real cuántas ganancias tiene disponibles para cobrar un inversor.
     * @param vaultId_ ID de la propiedad.
     * @param investor_ Wallet del inversor a consultar.
     * @return Rentas en USDC listas para ser reclamadas via `claimYield()`.
     */
    function getPendingYield(uint256 vaultId_, address investor_) public view returns (uint256) {
        uint256 userBalance = fractionalVault.balanceOf(investor_, vaultId_);
        if (userBalance == 0) return 0;

        uint256 totalEntitled = (userBalance * accYieldPerShare[vaultId_]) / PRECISION;
        uint256 alreadyPaid = userRewardPaid[vaultId_][investor_];

        if (totalEntitled <= alreadyPaid) return 0;

        return totalEntitled - alreadyPaid;
    }
}
