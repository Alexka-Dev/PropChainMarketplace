// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {Presale} from "@src/Presale.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockAggregator} from "@mocks/MockAggregator.sol";

// Mock of the Main Token with a Blacklist
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

contract MockStablecoin is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Auxiliary contract to force an ETH transfer failure in emergencyWithdraw
contract RejectETH {
    function withdraw(Presale presale) external {
        presale.emergencyWithdraw(address(0));
    }
}

contract PresaleTest is Test {
    Presale public presale;
    MockPropChainToken public saleToken;
    MockStablecoin public usdt;
    MockStablecoin public usdc;
    MockAggregator public ethPriceFeed;

    address public owner = address(this);
    address public buyer = address(0x100);
    address public blacklistedUser = address(0x200);

    int256 constant INITIAL_ETH_PRICE = 3000 * 1e8; // $3,000 USD (8 dec)
    uint256 constant TOKEN_PRICE_USD = 50000000; // $0.50 USD (8 dec)
    uint256 constant INITIAL_TOKENS = 10_000_000 * 1e18; // 10M CPT

    event TokensPurchased(
        address indexed buyer, address indexed assetAddress, uint256 amountSpent, uint256 tokensAllocated
    );

    event SetPaused(bool indexed isPaused);
    event TokenPriceUpdated(uint256 newTokenPriceInUsd);

    receive() external payable {}

    function setUp() public {
        saleToken = new MockPropChainToken();
        usdt = new MockStablecoin("Tether", "USDT");
        usdc = new MockStablecoin("USD Coin", "USDC");
        ethPriceFeed = new MockAggregator(8, INITIAL_ETH_PRICE);

        presale = new Presale(address(saleToken), address(usdt), address(usdc), address(ethPriceFeed));

        saleToken.mint(address(presale), INITIAL_TOKENS);

        // Buyer's funds
        vm.deal(buyer, 1000 ether);
        usdt.mint(buyer, 1_000_000 * 1e6);
        usdc.mint(buyer, 1_000_000 * 1e6);

        vm.startPrank(buyer);
        usdt.approve(address(presale), type(uint256).max);
        usdc.approve(address(presale), type(uint256).max);
        vm.stopPrank();

        // Setup Blacklist.
        saleToken.setBlacklist(blacklistedUser, true);
        vm.deal(blacklistedUser, 10 ether);
        usdt.mint(blacklistedUser, 1000 * 1e6);
        vm.prank(blacklistedUser);
        usdt.approve(address(presale), type(uint256).max);
    }

    // =========================================================
    // 1. CONSTRUCTOR & MODIFIERS
    // =========================================================

    function test_Constructor_ZeroAddressReverts() public {
        vm.expectRevert(Presale.InvalidAddress.selector);
        new Presale(address(0), address(usdt), address(usdc), address(ethPriceFeed));

        vm.expectRevert(Presale.InvalidAddress.selector);
        new Presale(address(saleToken), address(0), address(usdc), address(ethPriceFeed));

        vm.expectRevert(Presale.InvalidAddress.selector);
        new Presale(address(saleToken), address(usdt), address(0), address(ethPriceFeed));

        vm.expectRevert(Presale.InvalidAddress.selector);
        new Presale(address(saleToken), address(usdt), address(usdc), address(0));
    }

    function test_WhenNotPaused_RevertsIfPaused() public {
        presale.setPaused(true);

        vm.prank(buyer);
        vm.expectRevert(Presale.PresalePaused.selector);
        presale.buyWithETH{value: 1 ether}();

        vm.prank(buyer);
        vm.expectRevert(Presale.PresalePaused.selector);
        presale.buyWithStablecoin(address(usdt), 100 * 1e6);
    }

    // =========================================================
    // 2. BUY WITH ETH TESTS
    // =========================================================

    function test_BuyWithETH_RevertsIfZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert(Presale.InvalidAmount.selector);
        presale.buyWithETH{value: 0}();
    }

    function test_BuyWithETH_RevertsIfBlacklisted() public {
        vm.prank(blacklistedUser);
        vm.expectRevert(Presale.UserIsBlacklisted.selector);
        presale.buyWithETH{value: 1 ether}();
    }

    function test_BuyWithETH_RevertsIfInsufficientContractBalance() public {
        // Create a new presale with 0 tokens
        Presale emptyPresale = new Presale(address(saleToken), address(usdt), address(usdc), address(ethPriceFeed));

        vm.prank(buyer);
        vm.expectRevert(Presale.InsufficientContractBalance.selector);
        emptyPresale.buyWithETH{value: 1 ether}();
    }

    function test_BuyWithETH_Success() public {
        uint256 ethAmount = 2 ether;
        uint256 expectedTokens = 12_000 * 1e18;

        vm.expectEmit(true, true, false, true);
        emit TokensPurchased(buyer, address(0), ethAmount, expectedTokens);

        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();

        assertEq(saleToken.balanceOf(buyer), expectedTokens);
        assertEq(address(presale).balance, ethAmount);
    }

    // =========================================================
    // 3. BUY WITH STABLECOIN TESTS
    // =========================================================

    function test_BuyWithStablecoin_RevertsIfUnsupportedToken() public {
        MockStablecoin randomToken = new MockStablecoin("Random", "RND");

        vm.prank(buyer);
        vm.expectRevert(Presale.UnsupportedStablecoin.selector);
        presale.buyWithStablecoin(address(randomToken), 100 * 1e6);
    }

    function test_BuyWithStablecoin_RevertsIfZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert(Presale.InvalidAmount.selector);
        presale.buyWithStablecoin(address(usdt), 0);
    }

    function test_BuyWithStablecoin_RevertsIfBlacklisted() public {
        vm.prank(blacklistedUser);
        vm.expectRevert(Presale.UserIsBlacklisted.selector);
        presale.buyWithStablecoin(address(usdt), 100 * 1e6);
    }

    function test_BuyWithStablecoin_RevertsIfInsufficientContractBalance() public {
        Presale emptyPresale = new Presale(address(saleToken), address(usdt), address(usdc), address(ethPriceFeed));

        vm.prank(buyer);
        vm.expectRevert(Presale.InsufficientContractBalance.selector);
        emptyPresale.buyWithStablecoin(address(usdt), 500 * 1e6);
    }

    function test_BuyWithStablecoin_USDT_and_USDC_Success() public {
        uint256 stableAmount = 500 * 1e6; // $500 USD -> 1,000 CPT
        uint256 expectedTokens = 1_000 * 1e18;

        vm.expectEmit(true, true, false, true);
        emit TokensPurchased(buyer, address(usdt), stableAmount, expectedTokens);

        vm.prank(buyer);
        presale.buyWithStablecoin(address(usdt), stableAmount);
        assertEq(saleToken.balanceOf(buyer), expectedTokens);

        vm.prank(buyer);
        presale.buyWithStablecoin(address(usdc), stableAmount);
        assertEq(saleToken.balanceOf(buyer), expectedTokens * 2);
    }

    // =========================================================
    // 4. ADMIN FUNCTIONS TESTS
    // =========================================================

    function test_SetTokenPriceInUsd_RevertsIfZero() public {
        vm.expectRevert(Presale.InvalidAmount.selector);
        presale.setTokenPriceInUsd(0);
    }

    function test_SetTokenPriceInUsd_Success() public {
        uint256 newPrice = 100000000; // $1.00 USD
        vm.expectEmit(false, false, false, true);
        emit TokenPriceUpdated(newPrice);

        presale.setTokenPriceInUsd(newPrice);
        assertEq(presale.tokenPriceInUsd(), newPrice);
    }

    function test_SetPaused_Success() public {
        vm.expectEmit(true, false, false, false);
        emit SetPaused(true);

        presale.setPaused(true);
        assertTrue(presale.paused());

        presale.setPaused(false);
        assertFalse(presale.paused());
    }

    function test_EmergencyWithdraw_ETH_RevertsIfEmpty() public {
        vm.expectRevert(Presale.EmptyBalance.selector);
        presale.emergencyWithdraw(address(0));
    }

    function test_EmergencyWithdraw_ETH_Success() public {
        vm.prank(buyer);
        presale.buyWithETH{value: 5 ether}();

        uint256 ownerBalanceBefore = address(this).balance;
        presale.emergencyWithdraw(address(0));

        assertEq(address(this).balance, ownerBalanceBefore + 5 ether);
        assertEq(address(presale).balance, 0);
    }

    function test_EmergencyWithdraw_ETH_RevertsOnTransferFailure() public {
        RejectETH rejector = new RejectETH();

        presale.transferOwnership(address(rejector));

        vm.prank(buyer);
        presale.buyWithETH{value: 1 ether}();

        vm.expectRevert(Presale.ETHTransferFailed.selector);
        rejector.withdraw(presale);
    }

    function test_EmergencyWithdraw_Token_RevertsIfEmpty() public {
        MockStablecoin randomToken = new MockStablecoin("Empty", "MT");

        vm.expectRevert(Presale.EmptyBalance.selector);
        presale.emergencyWithdraw(address(randomToken));
    }

    function test_EmergencyWithdraw_Token_Success() public {
        usdt.mint(address(presale), 1000 * 1e6);

        uint256 ownerUsdtBefore = usdt.balanceOf(address(this));
        presale.emergencyWithdraw(address(usdt));

        assertEq(usdt.balanceOf(address(this)), ownerUsdtBefore + 1000 * 1e6);
        assertEq(usdt.balanceOf(address(presale)), 0);
    }

    // =========================================================
    // 5. ORACLE & HELPER CALCULATIONS TESTS
    // =========================================================

    function test_GetLatestEthPrice_RevertsOnZeroOrNegative() public {
        ethPriceFeed.setPrice(0);
        vm.expectRevert(Presale.InvalidOraclePrice.selector);
        presale.getLatestEthPrice();

        ethPriceFeed.setPrice(-500);
        vm.expectRevert(Presale.InvalidOraclePrice.selector);
        presale.getLatestEthPrice();
    }

    function test_CalculateEthPurchase_ReturnsZeroIfAmountZero() public view {
        assertEq(presale.calculateEthPurchase(0), 0);
    }

    function test_CalculateStablecoinPurchase_ReturnsZeroIfAmountZero() public view {
        assertEq(presale.calculateStablecoinPurchase(0), 0);
    }

    // =========================================================
    // 6. FUZZ TESTS
    // =========================================================

    function testFuzz_CalculateEthPurchase(uint96 ethAmount, int64 rawPrice) public {
        int256 price = bound(rawPrice, 100e8, 10000e8);
        ethPriceFeed.setPrice(price);

        ethAmount = uint96(bound(ethAmount, 0.001 ether, 1000 ether));

        uint256 tokens = presale.calculateEthPurchase(ethAmount);
        assertGt(tokens, 0);
    }

    function testFuzz_BuyWithStablecoin(uint32 stableAmountUnits) public {
        vm.assume(stableAmountUnits >= 1 && stableAmountUnits <= 1_000_000);

        uint256 amount = uint256(stableAmountUnits) * 1e6;
        uint256 expectedTokens = presale.calculateStablecoinPurchase(amount);

        vm.prank(buyer);
        presale.buyWithStablecoin(address(usdt), amount);

        assertEq(saleToken.balanceOf(buyer), expectedTokens);
    }
}
