// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title IFractionalVault
 * @notice Interfaz para la bóveda de fraccionamiento RWA ERC-1155.
 */
interface IFractionalVault is IERC1155 {
    struct Vault {
        address propertyContract;
        uint256 propertyTokenId;
        address originalOwner;
        uint256 totalFractions;
        uint256 availableFractions;
        uint256 pricePerFraction;
        bool isActive;
    }

    event PropertyFractionalized(
        uint256 indexed vaultId,
        address indexed propertyContract,
        uint256 indexed propertyTokenId,
        uint256 totalFractions,
        uint256 pricePerFraction
    );

    event FractionsPurchased(uint256 indexed vaultId, address indexed buyer, uint256 amount, uint256 totalPrice);

    function fractionalizeProperty(
        address propertyContract,
        uint256 propertyTokenId,
        uint256 totalFractions,
        uint256 pricePerFraction
    ) external returns (uint256);

    function buyFractions(uint256 vaultId, uint256 amount) external;

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
