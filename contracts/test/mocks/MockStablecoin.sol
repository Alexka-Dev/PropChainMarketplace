// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockStablecoin
 * @author BytePeak Technology
 * @notice Contrato mock para simular USDT/USDC localmente con 6 decimales.
 */
contract MockStablecoin is ERC20 {
    /**
     * @notice Constructor que inicializa la stablecoin falsa.
     * @param name Nombre del token.
     * @param symbol Símbolo del token.
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /**
     * @notice Mintea (crea) tokens falsos para pruebas.
     * @param to Dirección que recibirá los tokens.
     * @param amount Cantidad de tokens a mintear.
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Sobreescribe los decimales estándar de ERC20 para fijarlos en 6 (como USDT/USDC).
     * @return Cantidad de decimales del token (6).
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
