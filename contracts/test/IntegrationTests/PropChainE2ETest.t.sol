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
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockPropChainToken is ERC20, Ownable {
    mapping(address => bool) private _blacklist;

    constructor() ERC20("PropChain Token", "CPT") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlacklist(address account, bool value) external {
        _blacklist[account] = value;
    }

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklist[account];
    }
}

contract PropChainE2ETest is Test {
    PropChainMarketplace public marketplace;
    Presale public presale;
    MockPropChainToken public propChainToken;
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

        compliance = new MockComplianceRegistry();
        priceFeed = new MockAggregator(8, 3000 * 1e8); // ETH = $3,000 USD

        propChainToken = new MockPropChainToken();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        propertyNFT = new MockNFT();

        presale = new Presale(address(propChainToken), address(usdt), address(usdc), address(priceFeed));

        marketplace =
            new PropChainMarketplace(address(propChainToken), address(usdc), address(usdt), address(compliance), admin);

        compliance.setVerified(seller, true);
        compliance.setVerified(buyer, true);

        propChainToken.mint(address(presale), 1_000_000 * 1e18);

        vm.stopPrank();
    }

   function test_E2E_FullUserJourney() public {
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        presale.buyWithETH{value: 1 ether}();

        uint256 buyerBalance = propChainToken.balanceOf(buyer);
        assertTrue(buyerBalance > 0, "Buyer should have received CPT tokens");
        vm.stopPrank();

        vm.deal(seller, 1 ether); 
        vm.startPrank(seller);
        propertyNFT.mint(seller, 1);
        propertyNFT.approve(address(marketplace), 1);

        uint256 listingPrice = 1_000 * 1e18; 
        marketplace.listProperty{value: 0.01 ether}(
            address(propertyNFT), 1, 1, listingPrice, address(propChainToken), false
        );
        vm.stopPrank();

        vm.startPrank(buyer);
        propChainToken.approve(address(marketplace), listingPrice);
        marketplace.buyProperty(address(propertyNFT), 1);
        vm.stopPrank();

        assertEq(propertyNFT.ownerOf(1), buyer, "Buyer should now own the property NFT");
    }
}