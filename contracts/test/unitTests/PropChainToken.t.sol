// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.29;

/* solhint-disable func-name-mixedcase, ordering, func-order, import-path-check, one-contract-per-file */

import {Test} from "forge-std/Test.sol";
import {PropChainToken} from "../../src/PropChainToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @dev Harness para exponer la función interna _update y probar mints excedentes de CAP directamente
contract PropChainTokenHarness is PropChainToken {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 cap_,
        address initialReceiver
    ) PropChainToken(name_, symbol_, cap_, initialReceiver) {}

    function exposed_update(address from, address to, uint256 amount) external {
        _update(from, to, amount);
    }
}

contract PropChainTokenTest is Test {
    PropChainToken public token;

    address public admin = address(this);
    address public operator = address(0x10);
    address public user1 = address(0x100);
    address public user2 = address(0x200);

    uint256 public constant TOKEN_CAP = 100_000_000 * 1e18; // 100M CPT

    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);

    function setUp() public {
        token = new PropChainToken(
            "PropChain Token",
            "CPT",
            TOKEN_CAP,
            user1
        );

        // Conceder rol de operador de lista negra a `operator`
        token.grantRole(token.BLACKLIST_OPERATOR(), operator);
    }

    // =========================================================
    // 1. CONSTRUCTOR & INITIAL STATE TESTS
    // =========================================================

    function test_Constructor_RevertsIfZeroInitialReceiver() public {
        vm.expectRevert(PropChainToken.InvalidAddress.selector);
        new PropChainToken("PropChain", "CPT", TOKEN_CAP, address(0));
    }

    function test_Constructor_Success() public view {
        assertEq(token.name(), "PropChain Token");
        assertEq(token.symbol(), "CPT");
        assertEq(token.cap(), TOKEN_CAP);
        assertEq(token.CAP(), TOKEN_CAP);
        assertEq(token.totalSupply(), TOKEN_CAP);
        assertEq(token.balanceOf(user1), TOKEN_CAP);

        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.BLACKLIST_OPERATOR(), admin));
    }

    // =========================================================
    // 2. BLACKLIST MANAGEMENT TESTS & BRANCHES
    // =========================================================

    function test_AddToBlacklist_RevertsIfNotOperator() public {
        address nonOperator = address(0x100);
        bytes32 operatorRole = token.BLACKLIST_OPERATOR();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonOperator,
                operatorRole
            )
        );

        vm.prank(nonOperator);
        token.addToBlacklist(address(0x200));
    }

    function test_AddToBlacklist_RevertsIfZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(PropChainToken.InvalidAddress.selector);
        token.addToBlacklist(address(0));
    }

    function test_AddToBlacklist_Success() public {
        vm.expectEmit(true, false, false, false);
        emit AddedToBlacklist(user2);

        vm.prank(operator);
        token.addToBlacklist(user2);

        assertTrue(token.isBlacklisted(user2));
        assertTrue(token.blacklist(user2));
    }

    function test_RemoveFromBlacklist_RevertsIfNotOperator() public {
        address authorizedOperator = address(0x10);
        address nonOperator = address(0x100);
        bytes32 operatorRole = token.BLACKLIST_OPERATOR();

        vm.prank(authorizedOperator);
        token.addToBlacklist(address(0x200));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonOperator,
                operatorRole
            )
        );

        vm.prank(nonOperator);
        token.removeFromBlacklist(address(0x200));
    }

    function test_RemoveFromBlacklist_RevertsIfZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(PropChainToken.InvalidAddress.selector);
        token.removeFromBlacklist(address(0));
    }

    function test_RemoveFromBlacklist_Success() public {
        vm.prank(operator);
        token.addToBlacklist(user2);
        assertTrue(token.isBlacklisted(user2));

        vm.expectEmit(true, false, false, false);
        emit RemovedFromBlacklist(user2);

        vm.prank(operator);
        token.removeFromBlacklist(user2);

        assertFalse(token.isBlacklisted(user2));
    }

    // =========================================================
    // 3. TRANSFER & BLACKLIST INTERCEPTION TESTS (_update)
    // =========================================================

    function test_Transfer_RevertsIfSenderIsBlacklisted() public {
        vm.prank(operator);
        token.addToBlacklist(user1);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(PropChainToken.AddressBlacklisted.selector, user1)
        );
        token.transfer(user2, 100 * 1e18);
    }

    function test_Transfer_RevertsIfRecipientIsBlacklisted() public {
        vm.prank(operator);
        token.addToBlacklist(user2);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(PropChainToken.AddressBlacklisted.selector, user2)
        );
        token.transfer(user2, 100 * 1e18);
    }

    function test_Transfer_SuccessWhenNotBlacklisted() public {
        uint256 amount = 1_000 * 1e18;

        vm.prank(user1);
        bool success = token.transfer(user2, amount);
        assertTrue(success);

        assertEq(token.balanceOf(user2), amount);
        assertEq(token.balanceOf(user1), TOKEN_CAP - amount);
    }

    // =========================================================
    // 4. BURN & CAP EXCEEDED TESTS
    // =========================================================

    function test_Burn_SuccessAndDecreasesTotalSupply() public {
        uint256 burnAmount = 10_000 * 1e18;

        vm.prank(user1);
        token.burn(burnAmount);

        assertEq(token.totalSupply(), TOKEN_CAP - burnAmount);
        assertEq(token.balanceOf(user1), TOKEN_CAP - burnAmount);
    }

    function test_BurnFrom_Success() public {
        uint256 burnAmount = 5_000 * 1e18;

        vm.prank(user1);
        token.approve(user2, burnAmount);

        vm.prank(user2);
        token.burnFrom(user1, burnAmount);

        assertEq(token.totalSupply(), TOKEN_CAP - burnAmount);
    }

    function test_CapExceeded_RevertsIfProjectedSupplyExceedsCap() public {
        uint256 lowCap = 1_000 * 1e18;

        PropChainTokenHarness harness = new PropChainTokenHarness(
            "Harness",
            "HAR",
            lowCap,
            user1
        );

        vm.prank(user1);
        harness.burn(100 * 1e18);

        uint256 requestedAmount = 200 * 1e18;
        uint256 projectedSupply = harness.totalSupply() + requestedAmount;

        vm.expectRevert(
            abi.encodeWithSelector(
                PropChainToken.CapExceeded.selector,
                projectedSupply,
                lowCap
            )
        );
        harness.exposed_update(address(0), user2, requestedAmount);
    }

    // =========================================================
    // 5. FUZZ TESTS
    // =========================================================

    function testFuzz_Transfer(uint96 amount) public {
        vm.assume(amount > 0 && amount < TOKEN_CAP + 1);

        vm.prank(user1);
        bool success = token.transfer(user2, amount);
        assertTrue(success);

        assertEq(token.balanceOf(user2), amount);
        assertEq(token.balanceOf(user1), TOKEN_CAP - amount);
    }
}
/* solhint-enable func-name-mixedcase, ordering, func-order, import-path-check, one-contract-per-file */