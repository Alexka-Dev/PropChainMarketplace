// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {PropChainMarketplace} from "@src/PropChainMarketplace.sol";

contract MockComplianceRegistry {
    mapping(address => bool) public verifiedUsers;

    function setVerified(address account, bool status) external {
        verifiedUsers[account] = status;
    }

    function isVerified(address account) external view returns (bool) {
        return verifiedUsers[account];
    }
}

/**
 * @title PropChainMarketplaceTest
 * @author BytePeak Technology
 * @notice Suite de pruebas en Foundry adaptada a la implementación de PropChainMarketplace.
 */
contract PropChainMarketplaceTest is Test {
    PropChainMarketplace public marketplace;
    MockComplianceRegistry public complianceRegistry;

    address public admin = makeAddr("admin");
    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");
    address public propChainToken = makeAddr("propChainToken");
    address public usdc = makeAddr("usdc");
    address public usdt = makeAddr("usdt");
    address public mockNFT = makeAddr("mockNFT");

    uint256 public constant TOKEN_ID = 1;
    uint256 public constant AMOUNT = 1;
    uint256 public constant PRICE = 1 ether;
    uint256 public constant LISTING_FEE = 0.01 ether;

    function setUp() public {
        complianceRegistry = new MockComplianceRegistry();

        // Marcar vendedor y comprador como verificados en KYC
        complianceRegistry.setVerified(seller, true);
        complianceRegistry.setVerified(buyer, true);

        // Despliegue del Marketplace pasándole los 5 parámetros requeridos
        vm.prank(admin);
        marketplace = new PropChainMarketplace(
            propChainToken,
            usdc,
            usdt,
            address(complianceRegistry),
            admin
        );

        vm.deal(seller, 10 ether);
        vm.deal(buyer, 10 ether);
    }

    // ---------------------------------------------------------
    // 1. Pruebas de Despliegue y Configuración
    // ---------------------------------------------------------

    function test_Constructor_SetsCorrectState() public view {
        assertEq(marketplace.feeRecipient(), admin);
        assertEq(address(marketplace.complianceRegistry()), address(complianceRegistry));
        assertTrue(marketplace.isAcceptedPaymentToken(address(0)));
        assertTrue(marketplace.isAcceptedPaymentToken(propChainToken));
        assertTrue(marketplace.isAcceptedPaymentToken(usdc));
        assertTrue(marketplace.isAcceptedPaymentToken(usdt));
    }

    // ---------------------------------------------------------
    // 2. Publicación (listProperty - 6 argumentos)
    // ---------------------------------------------------------

    function test_ListProperty_RevertIf_IncorrectListingFee() public {
        vm.startPrank(seller);
        vm.expectRevert(PropChainMarketplace.IncorrectListingFee.selector);
        
        // 6 argumentos
        marketplace.listProperty(
            mockNFT,
            TOKEN_ID,
            AMOUNT,
            PRICE,
            address(0),
            false
        );
        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // 3. Cancelación de Publicación (cancelListing - 2 argumentos)
    // ---------------------------------------------------------

    function test_CancelListing_RevertIf_NotListingOwner() public {
        vm.startPrank(seller);
        
        // 2 argumentos: nftAddress y tokenId
        vm.expectRevert(PropChainMarketplace.NotListingOwner.selector);
        marketplace.cancelListing(mockNFT, TOKEN_ID);
        
        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // 4. Actualización de Precio (updateListingPrice - 3 argumentos)
    // ---------------------------------------------------------

    function test_UpdateListingPrice_RevertIf_ZeroPrice() public {
        vm.startPrank(seller);
        
        // 3 argumentos: nftAddress, tokenId y newPrice
        vm.expectRevert(PropChainMarketplace.PriceMustBeGreaterThanZero.selector);
        marketplace.updateListingPrice(mockNFT, TOKEN_ID, 0);
        
        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // 5. Compra (buyProperty - 2 argumentos)
    // ---------------------------------------------------------

    function test_BuyProperty_RevertIf_NotListed() public {
        vm.startPrank(buyer);
        
        // 2 argumentos: nftAddress y tokenId
        vm.expectRevert(PropChainMarketplace.NFTNotListed.selector);
        marketplace.buyProperty{value: PRICE}(mockNFT, TOKEN_ID);
        
        vm.stopPrank();
    }
}