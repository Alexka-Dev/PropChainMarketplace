// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IComplianceRegistry} from "./Interfaces/IComplianceRegistry.sol";

/**
 * @title ComplianceRegistry
 * @author BytePeak Technology
 * @notice Contrato registro de identidades KYC/AML para habilitar la interacción con RWA.
 */
contract ComplianceRegistry is IComplianceRegistry, AccessControl {
    // ---------------------------------------------------------
    // Roles & State Variables
    // ---------------------------------------------------------

    /// @notice Rol asignado a los oráculos o administradores encargados de aprobar KYC.
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    /// @notice Mapeo de dirección de wallet => Estado de aprobación KYC.
    mapping(address => bool) private _verifiedUsers;

    /// @notice Mapeo opcional de dirección de wallet => Hash de referencia del expediente KYC.
    mapping(address => string) private _kycHashes;

    // ---------------------------------------------------------
    // Custom Errors
    // ---------------------------------------------------------

    error ZeroAddressDetected();
    error AlreadyVerified();
    error NotVerified();

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------

    constructor(address admin_) {
        if (admin_ == address(0)) revert ZeroAddressDetected();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(VERIFIER_ROLE, admin_);
    }

    // ---------------------------------------------------------
    // External / Public Functions
    // ---------------------------------------------------------

    /**
     * @notice Registra y aprueba a un usuario verificado.
     */
    function verifyUser(address account, string calldata kycHash) external onlyRole(VERIFIER_ROLE) {
        if (account == address(0)) revert ZeroAddressDetected();
        if (_verifiedUsers[account]) revert AlreadyVerified();

        _verifiedUsers[account] = true;
        _kycHashes[account] = kycHash;

        emit UserVerified(account, kycHash);
    }

    /**
     * @notice Revoca la aprobación de una wallet.
     */
    function revokeUser(address account) external onlyRole(VERIFIER_ROLE) {
        if (!_verifiedUsers[account]) revert NotVerified();

        _verifiedUsers[account] = false;
        delete _kycHashes[account];

        emit UserRevoked(account);
    }

    /**
     * @notice Devuelve si una cuenta está verificada.
     */
    function isVerified(address account) external view override returns (bool) {
        return _verifiedUsers[account];
    }
}