// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
/* solhint-disable no-console */
import {console2} from "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PropertiesCollection} from "../src/PropertiesCollection.sol";
import {PropChainMarketplace} from "../src/PropChainMarketplace.sol";
import {PropChainToken} from "../src/PropChainToken.sol";
import {Presale} from "../src/Presale.sol";

/**
 * @title DeployAll
 * @author BytePeak Technology
 * @notice Script de orquestación automatizada para el despliegue del ecosistema PropTech.
 * @dev Ejecuta secuencialmente la inicialización de colecciones, marketplaces, tokens RWA y contratos de preventa.
 */
contract DeployAll is Script {
    using SafeERC20 for IERC20;

    /* solhint-disable max-states-count, code-complexity */
    /**
     * @notice Punto de entrada principal para la ejecución del script de despliegue.
     */
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Parámetros de prueba con Checksum EIP-55 corregido
        address usdtTestnet = 0xB693bEbF008bDac3804d9c69493a7f129e3060e4;
        address usdcTestnet = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
        address ethUsdPriceFeed = 0xd30E2101A97D0ADBCB232123927A31583b90bf17;

        /* solhint-disable gas-small-strings */
        console2.log("Starting deployment from:", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // PASO 1: Colección NFT
        PropertiesCollection collection = new PropertiesCollection(
            "PropChain Collection", "PCT", 10, "ipfs://QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco/"
        );
        console2.log("PropertiesCollection deployed at:", address(collection));

        // PASO 2: Token de Fracciones
        uint256 totalFractions = 100_000;
        PropChainToken tokenProperty0 = new PropChainToken("Apartment 4B Miami", "CPT", totalFractions, deployerAddress);
        console2.log("PropChainToken deployed at:", address(tokenProperty0));

        // PASO 3: Marketplace (Requiere 5 argumentos: initialPropChainToken, usdcAddress, usdtAddress, complianceRegistry, admin)
        PropChainMarketplace marketplace = new PropChainMarketplace(
            address(tokenProperty0),
            usdcTestnet,
            usdtTestnet,
            deployerAddress, // Compliance Registry temporal
            deployerAddress // Admin
        );
        console2.log("PropChainMarketplace deployed at:", address(marketplace));

        // PASO 4: Despliegue de la Preventa
        Presale presale = new Presale(address(tokenProperty0), usdtTestnet, usdcTestnet, ethUsdPriceFeed);
        console2.log("Presale deployed at:", address(presale));

        // PASO 5: Transferir tokens a la Preventa para financiarla
        uint256 presaleSupply = totalFractions * 1e18;
        IERC20(address(tokenProperty0)).safeTransfer(address(presale), presaleSupply);
        console2.log("Transferred", presaleSupply, "tokens to Presale contract.");

        vm.stopBroadcast();
        /* solhint-enable gas-small-strings */
    }
}
/* solhint-enable no-console */