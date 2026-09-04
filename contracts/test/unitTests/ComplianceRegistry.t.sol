// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {ComplianceRegistry} from "@src/ComplianceRegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title ComplianceRegistryTest
 * @author BytePeak Technology
 * @notice Suite de pruebas en Foundry para validar ComplianceRegistry.
 */
contract ComplianceRegistryTest is Test {
    ComplianceRegistry public registry;

    address public admin = makeAddr("admin");
    address public verifier = makeAddr("verifier");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public unauthorized = makeAddr("unauthorized");

    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    string public constant KYC_URI = "ipfs://QmKYCHashExample";

    event UserVerified(address indexed user);
    event UserUnverified(address indexed user);

    function setUp() public {
        vm.startPrank(admin);
        registry = new ComplianceRegistry(admin);
        registry.grantRole(VERIFIER_ROLE, verifier);
        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // 1. Constructor & Deployment
    // ---------------------------------------------------------

    function test_Constructor_SetsRolesCorrectly() public view {
        assertTrue(registry.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(registry.hasRole(VERIFIER_ROLE, admin));
        assertTrue(registry.hasRole(VERIFIER_ROLE, verifier));
    }

    function test_Constructor_RevertIf_ZeroAddressAdmin() public {
        vm.expectRevert(ComplianceRegistry.ZeroAddressDetected.selector);
        new ComplianceRegistry(address(0));
    }

    // ---------------------------------------------------------
    // 2. Single User Verification
    // ---------------------------------------------------------

    function test_VerifyUser_Success() public {
        vm.expectEmit(true, false, false, false);
        emit UserVerified(user1);

        vm.prank(verifier);
        registry.verifyUser(user1, KYC_URI);

        assertTrue(registry.isVerified(user1));
    }

    function test_VerifyUser_RevertIf_Unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, VERIFIER_ROLE
            )
        );
        registry.verifyUser(user1, KYC_URI);
    }

    function test_VerifyUser_RevertIf_ZeroAddress() public {
        vm.prank(verifier);
        vm.expectRevert(ComplianceRegistry.ZeroAddressDetected.selector);
        registry.verifyUser(address(0), KYC_URI);
    }

    // ---------------------------------------------------------
    // 3. Batch Verification
    // ---------------------------------------------------------

    function test_BatchVerify_Iterative_Success() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.startPrank(verifier);
        for (uint256 i = 0; i < users.length; i++) {
            registry.verifyUser(users[i], KYC_URI);
        }
        vm.stopPrank();

        assertTrue(registry.isVerified(user1));
        assertTrue(registry.isVerified(user2));
    }

    // ---------------------------------------------------------
    // 4. View Function Edge Cases
    // ---------------------------------------------------------

    function test_IsVerified_ReturnsFalseForUnverifiedAndZero() public view {
        assertFalse(registry.isVerified(user1));
        assertFalse(registry.isVerified(address(0)));
    }
}
