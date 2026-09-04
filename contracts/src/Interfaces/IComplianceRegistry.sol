// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/**
 * @title IComplianceRegistry
 * @author BytePeak Technology
 * @notice Interfaz para la gestión y consulta de cumplimiento legal KYC/AML para activos RWA.
 */
interface IComplianceRegistry {
    // ---------------------------------------------------------
    // Events
    // ---------------------------------------------------------
    event UserVerified(address indexed account, string kycHash);
    event UserRevoked(address indexed account);

    // ---------------------------------------------------------
    // View Functions
    // ---------------------------------------------------------

    /**
     * @notice Consulta si una dirección tiene verificación KYC/AML activa.
     * @param account Dirección de la wallet a verificar.
     * @return bool True si la cuenta está aprobada, false en caso contrario.
     */
    function isVerified(address account) external view returns (bool);

    // ---------------------------------------------------------
    // State-Changing Functions
    // ---------------------------------------------------------

    /**
     * @notice Aprueba una wallet tras completar exitosamente el proceso KYC/AML.
     * @param account Wallet del inversor/usuario.
     * @param kycHash Identificador o hash cifrado del expediente KYC en la entidad verificadora.
     */
    function verifyUser(address account, string calldata kycHash) external;

    /**
     * @notice Revoca el acceso a una wallet (ej. pérdida de verificación o sanción legal).
     * @param account Wallet a desautorizar.
     */
    function revokeUser(address account) external;
}