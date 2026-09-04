// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity ^0.8.29;

/* solhint-disable func-name-mixedcase, ordering, func-order, import-path-check, one-contract-per-file */

import {Test, console} from "forge-std/Test.sol";
import {PropChainToken} from "../../src/PropChainToken.sol";
import {PropertiesCollection} from "../../src/PropertiesCollection.sol";
import {Presale} from "../../src/Presale.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PresaleIntegrationTest is Test {
    // Instances of Real Contracts and Mocks
    PropChainToken public token;
    PropertiesCollection public collection;
    Presale public presale;
    MockAggregator public priceFeed;

    // Payment Tokens and Accounts
    address public usdt = address(0x1111);
    address public usdc = address(0x1222);

    address public admin = address(0xAD1);
    address public treasury = address(0x1EA5);
    address public seller = address(0x5E11);
    address public buyer1 = address(0xB11);
    address public buyer2 = address(0xB22);

    // Initial Setup
    string public constant TOKEN_NAME = "PropChain Token";
    string public constant TOKEN_SYMBOL = "PCT";
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant PRESALE_TOKEN_ALLOCATION = 500_000 * 1e18;

    uint256 public constant MAX_NFT_SUPPLY = 10;
    string public constant BASE_URI = "ipfs://QmZillowWeb3Properties/";

    function setUp() public {
        vm.startPrank(admin);

        token = new PropChainToken(TOKEN_NAME, TOKEN_SYMBOL, INITIAL_SUPPLY, admin);

        collection = new PropertiesCollection("PropChain Properties", "PCP", MAX_NFT_SUPPLY, BASE_URI);

        priceFeed = new MockAggregator(8, 3000 * 1e8);

        presale = new Presale(address(token), usdt, usdc, address(priceFeed));

        // Transfer the token allocation to the presale
        bool success = token.transfer(address(presale), PRESALE_TOKEN_ALLOCATION);
        assertTrue(success);

        vm.stopPrank();

        vm.deal(buyer1, 10 ether);
        vm.deal(buyer2, 10 ether);
    }

    // ---------------------------------------------------------
    // Integrated (End-to-End) Workflows
    // ---------------------------------------------------------

    function test_Integration_InitialStateAndWiring() public view {
        assertEq(address(presale.SALE_TOKEN()), address(token));
        assertEq(address(presale.ETH_USD_PRICE_FEED()), address(priceFeed));
        assertEq(token.balanceOf(address(presale)), PRESALE_TOKEN_ALLOCATION);
    }

    /**
     * @dev Full End-to-End Workflow:
     * 1. The admin mints an NFT for the seller.
     * 2. Buyer1 participates in the presale by interacting with Presale.
     * 3. Value transfers and balances are verified.
     */
    function test_Integration_FullPurchaseFlow() public {
        // Step 1: Admin mintea la propiedad NFT para el vendedor
        vm.prank(admin);
        uint256 propertyId = collection.mintTo(seller);
        assertEq(collection.ownerOf(propertyId), seller);

        // Step 2: Verificación de balance del contrato de preventa
        assertEq(token.balanceOf(address(presale)), PRESALE_TOKEN_ALLOCATION);

        // Step 3: Si la presale tiene un método de compra con ETH (ej. buyWithETH):

        vm.prank(buyer1);
        presale.buyWithETH{value: 1 ether}();
        assertGt(token.balanceOf(buyer1), 0);
    }

    /**
     * @dev See how the token's blacklist restricts interactions within the ecosystem.
     */
    function test_Integration_BlacklistedUserCannotParticipate() public {
        bytes32 operatorRole = token.BLACKLIST_OPERATOR();

        // Assign the "operator" role and add "buyer1" to the blacklist
        vm.startPrank(admin);
        token.grantRole(operatorRole, admin);
        token.addToBlacklist(buyer1);
        vm.stopPrank();

        assertTrue(token.isBlacklisted(buyer1));

        // Direct transfer of tokens to buyer1 should fail
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(PropChainToken.AddressBlacklisted.selector, buyer1));
        token.transfer(buyer1, 100 * 1e18);
    }
}
