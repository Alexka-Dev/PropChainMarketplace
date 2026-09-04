// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {PropChainMarketplace} from "@src/PropChainMarketplace.sol";
import {Presale} from "@src/Presale.sol";
import {MockERC20} from "@mocks/MockERC20.sol";
import {MockNFT} from "@mocks/MockNFT.sol";
import {MockComplianceRegistry} from "@mocks/MockComplianceRegistry.sol";
import {MockAggregator} from "@mocks/MockAggregator.sol";

contract PropChainE2ETest is Test {
    PropChainMarketplace public marketplace;
    Presale public presale;
    MockERC20 public propChainToken;
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockNFT public propertyNFT;
    MockComplianceRegistry public compliance;
    MockAggregator public priceFeed;

    address public admin = address(1);
    address public seller = address(2);
    address public buyer = address(3);

    function setUp() public {
        vm.startPrank(admin);

        // 1. Mocks & Infra
        compliance = new MockComplianceRegistry();
        priceFeed = new MockAggregator(8, 3000 * 1e8); // ETH = $3,000 USD

        propChainToken = new MockERC20("PropChain Token", "CPT", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        propertyNFT = new MockNFT();

        // 2. Deploy Contratos Principales
        presale = new Presale(address(propChainToken), address(usdt), address(usdc), address(priceFeed));

        marketplace =
            new PropChainMarketplace(address(propChainToken), address(usdc), address(usdt), address(compliance), admin);

        // 3. Setup KYC & Tokens
        compliance.setVerified(seller, true);
        compliance.setVerified(buyer, true);

        // Fondear la Presale con tokens para venta
        propChainToken.mint(address(presale), 1_000_000 * 1e18);

        vm.stopPrank();
    }

    function test_E2E_FullUserJourney() public {
        // Step 1: Comprar tokens CPT en la Presale
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        presale.buyWithETH{value: 1 ether}();

        uint256 buyerBalance = propChainToken.balanceOf(buyer);
        assertTrue(buyerBalance > 0, "Buyer should have received CPT tokens");
        vm.stopPrank();

        // Step 2: Vendedor lista propiedad en el Marketplace aceptando CPT
        vm.startPrank(seller);
        propertyNFT.mint(seller, 1);
        propertyNFT.approve(address(marketplace), 1);

        uint256 listingPrice = 1_000 * 1e18; // 1,000 CPT
        marketplace.listProperty{value: 0.01 ether}(
            address(propertyNFT), 1, 1, listingPrice, address(propChainToken), false
        );
        vm.stopPrank();

        // Step 3: Comprador aprueba Marketplace y compra la propiedad con tokens CPT de la presale
        vm.startPrank(buyer);
        propChainToken.approve(address(marketplace), listingPrice);
        marketplace.buyProperty(address(propertyNFT), 1);
        vm.stopPrank();

        // Assertions finales
        assertEq(propertyNFT.ownerOf(1), buyer, "Buyer should now own the property NFT");
    }
}
