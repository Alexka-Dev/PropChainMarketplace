// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ICrownPropertyCollection {
    function safeMint(address to) external returns (uint256);
}

interface IFractionalVault {
    function fractionalizeProperty(
        address propertyContract,
        uint256 propertyTokenId,
        uint256 totalFractions,
        uint256 pricePerFraction
    ) external returns (uint256);
}

interface IComplianceRegistry {
    function isVerified(address account) external view returns (bool);
}

/**
 * @title PropertyFactory
 * @author BytePeak Technology
 * @notice Fábrica orquestadora para el registro, minteo y fraccionalización estandarizada de propiedades RWA.
 * @dev Sigue el patrón CEI, ReentrancyGuard, control de acceso granular y verificación KYC.
 */
contract PropertyFactory is AccessControl, ReentrancyGuard {
    // ---------------------------------------------------------
    // 1. Roles & State Variables
    // ---------------------------------------------------------

    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    /// @notice Dirección del contrato de colección de NFTs de propiedades (ERC-721).
    ICrownPropertyCollection public immutable propertyCollection;

    /// @notice Dirección del contrato de bóveda fraccional (ERC-1155).
    IFractionalVault public immutable fractionalVault;

    /// @notice Dirección del contrato de registro KYC.
    IComplianceRegistry public complianceRegistry;

    /// @notice Estratificación de la cuota mínima estandarizada ($100 en unidades del token de pago).
    uint256 public constant MIN_PRICE_PER_FRACTION = 100_000_000; // 100 USDC (6 decimales)

    // ---------------------------------------------------------
    // 2. Events
    // ---------------------------------------------------------

    event PropertyCreatedAndFractionalized(
        uint256 indexed propertyTokenId,
        uint256 indexed vaultId,
        address indexed owner,
        uint256 totalFractions,
        uint256 pricePerFraction
    );

    event ComplianceRegistryUpdated(address indexed newRegistry);

    // ---------------------------------------------------------
    // 3. Custom Errors
    // ---------------------------------------------------------

    error ZeroAddressDetected();
    error OwnerNotKYCVerified(address owner);
    error InvalidFractionCount();
    error PriceBelowMinimum();

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------

    constructor(address propertyCollection_, address fractionalVault_, address complianceRegistry_, address admin_) {
        if (
            propertyCollection_ == address(0) || fractionalVault_ == address(0) || complianceRegistry_ == address(0)
                || admin_ == address(0)
        ) {
            revert ZeroAddressDetected();
        }

        propertyCollection = ICrownPropertyCollection(propertyCollection_);
        fractionalVault = IFractionalVault(fractionalVault_);
        complianceRegistry = IComplianceRegistry(complianceRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(VERIFIER_ROLE, admin_);
    }

    // ---------------------------------------------------------
    // External Functions (Patrón CEI Compliant)
    // ---------------------------------------------------------

    /**
     * @notice Mintea el NFT de la propiedad y lo fracciona de forma atómica bajo reglas estandarizadas.
     * @param propertyOwner_ Dirección del propietario real/LLC que recibe los beneficios de la venta.
     * @param totalFractions_ Cantidad total de cuotas en las que se dividirá la propiedad.
     * @param pricePerFraction_ Precio por fracción en USDC (mínimo 100 USDC).
     */
    function createAndFractionalizeProperty(address propertyOwner_, uint256 totalFractions_, uint256 pricePerFraction_)
        external
        onlyRole(VERIFIER_ROLE)
        nonReentrant
        returns (uint256 propertyTokenId, uint256 vaultId)
    {
        // --- CHECKS ---
        if (propertyOwner_ == address(0)) revert ZeroAddressDetected();
        if (!complianceRegistry.isVerified(propertyOwner_)) revert OwnerNotKYCVerified(propertyOwner_);
        if (totalFractions_ == 0) revert InvalidFractionCount();
        if (pricePerFraction_ < MIN_PRICE_PER_FRACTION) revert PriceBelowMinimum();

        // --- INTERACTIONS & EFFECTS ---
        // 1. Mintear el NFT ERC-721 enviándolo directamente a este contrato Fábrica
        propertyTokenId = propertyCollection.safeMint(address(this));

        // 2. Aprobar al FractionalVault para que pueda tomar la custodia del NFT
        IERC721(address(propertyCollection)).approve(address(fractionalVault), propertyTokenId);

        // 3. Depositar el NFT en la bóveda e iniciar el fraccionamiento
        vaultId = fractionalVault.fractionalizeProperty(
            address(propertyCollection), propertyTokenId, totalFractions_, pricePerFraction_
        );

        emit PropertyCreatedAndFractionalized(
            propertyTokenId, vaultId, propertyOwner_, totalFractions_, pricePerFraction_
        );

        return (propertyTokenId, vaultId);
    }

    /**
     * @notice Permite actualizar el registro KYC.
     */
    function setComplianceRegistry(address newRegistry_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRegistry_ == address(0)) revert ZeroAddressDetected();
        complianceRegistry = IComplianceRegistry(newRegistry_);
        emit ComplianceRegistryUpdated(newRegistry_);
    }
}
