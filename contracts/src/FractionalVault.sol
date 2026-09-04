// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IComplianceRegistry {
    function isVerified(address account) external view returns (bool);
}

/**
 * @title FractionalVault
 * @author BytePeak Technology
 * @notice Bóveda de fraccionamiento de RWA optimizada en gas y ajustada a las reglas de linter.
 */
contract FractionalVault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------
    // 1. Structs (Van PRIMERO según la guía de estilo)
    // ---------------------------------------------------------

    /**
     * @notice Estructura optimizada para almacenamiento en slot (32-byte alignment).
     * @dev Slot 1: address (20B) + uint96 (12B) = 32B
     *      Slot 2: address (20B) + uint96 (12B) = 32B
     *      Slot 3: uint256 (32B)
     *      Slot 4: bool (1B) + padding
     */
    struct Vault {
        address propertyOwner; // 20 bytes \ Slot 1
        uint96 totalFractions; // 12 bytes / (Suma 32 bytes)
        address nftAddress; // 20 bytes \ Slot 2
        uint96 pricePerFraction; // 12 bytes / (Suma 32 bytes)
        uint256 propertyId; // 32 bytes (Slot 3)
        bool isFractionalized; // 1 byte   (Slot 4)
    }

    // ---------------------------------------------------------
    // 2. Constants & Immutable Variables (UPPER_SNAKE_CASE)
    // ---------------------------------------------------------

    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    /// @notice Direcciones inmutables en convención UPPER_SNAKE_CASE
    IComplianceRegistry public immutable COMPLIANCE_REGISTRY;
    IERC20 public immutable PROP_CHAIN_TOKEN;

    // ---------------------------------------------------------
    // 3. State Variables
    // ---------------------------------------------------------

    mapping(uint256 => Vault) public vaults;

    // ---------------------------------------------------------
    // 4. Events (Parametros indexados actualizados)
    // ---------------------------------------------------------

    event VaultCreated(
        uint256 indexed propertyId,
        address indexed propertyOwner,
        address indexed nftAddress,
        uint96 totalFractions,
        uint96 pricePerFraction
    );

    event FractionsPurchased(
        uint256 indexed propertyId, address indexed buyer, uint256 indexed amount, uint256 totalPrice
    );

    event FractionsRedeemed(uint256 indexed propertyId, address indexed redeemer, uint256 amount);

    // ---------------------------------------------------------
    // 5. Custom Errors
    // ---------------------------------------------------------

    error InvalidAddress();
    error ZeroAmount();
    error UserNotKYCVerified(address user);

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------

    constructor(address complianceRegistry_, address propChainToken_, address admin_) {
        if (complianceRegistry_ == address(0) || propChainToken_ == address(0) || admin_ == address(0)) {
            revert InvalidAddress();
        }

        COMPLIANCE_REGISTRY = IComplianceRegistry(complianceRegistry_);
        PROP_CHAIN_TOKEN = IERC20(propChainToken_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(VAULT_MANAGER_ROLE, admin_);
    }

    // ---------------------------------------------------------
    // External & Public Functions
    // ---------------------------------------------------------

    function buyFractions(uint256 propertyId_, uint96 amount_) external nonReentrant {
        if (amount_ == 0) revert ZeroAmount();
        if (!COMPLIANCE_REGISTRY.isVerified(msg.sender)) {
            revert UserNotKYCVerified(msg.sender);
        }

        Vault storage vault = vaults[propertyId_];
        uint256 totalPrice = uint256(amount_) * uint256(vault.pricePerFraction);

        PROP_CHAIN_TOKEN.safeTransferFrom(msg.sender, vault.propertyOwner, totalPrice);

        emit FractionsPurchased(propertyId_, msg.sender, amount_, totalPrice);
    }
}
