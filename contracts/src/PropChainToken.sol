// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PropChainToken
 * @author BytePeak Technology
 * @notice Utility and governance ERC20 token for the PropChain ecosystem.
 * @dev Includes AccessControl, supply capping, and blacklisting features for compliance.
 */
contract PropChainToken is ERC20, ERC20Burnable, AccessControl {

    // ---------------------------------------------------------
    // 1. Roles & Immutable Variables
    // ---------------------------------------------------------

    bytes32 public constant BLACKLIST_OPERATOR = keccak256("BLACKLIST_OPERATOR");
    
    /// @notice Absolute maximum supply of tokens (in smallest unit / wei).
    uint256 public immutable CAP;

    // ---------------------------------------------------------
    // 2. State Variables
    // ---------------------------------------------------------

    mapping(address => bool) public blacklist;

    // ---------------------------------------------------------
    // 3. Events
    // ---------------------------------------------------------

    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);

    // ---------------------------------------------------------
    // 4. Custom Errors
    // ---------------------------------------------------------

    error AddressBlacklisted(address blacklistedAddress);
    error CapExceeded(uint256 requestedSupply, uint256 maxCap);
    error InvalidAddress();

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------

    /**
     * @param name_ Descriptive name of the token.
     * @param symbol_ Token symbol.
     * @param cap_ Strict supply limit IN WEI (include 18 decimals in parameter).
     * @param initialReceiver Wallet address to receive the initial minted supply.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 cap_,
        address initialReceiver
    ) ERC20(name_, symbol_) {
        if (initialReceiver == address(0)) revert InvalidAddress();

        CAP = cap_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BLACKLIST_OPERATOR, msg.sender);

        // Mint initial supply up to CAP directly to designated receiver
        _mint(initialReceiver, cap_);
    }

    // ---------------------------------------------------------
    // Compliance / Blacklist Logic
    // ---------------------------------------------------------

    /**
     * @notice Restricts an account from sending or receiving tokens.
     */
    function addToBlacklist(address account) external onlyRole(BLACKLIST_OPERATOR) {
        if (account == address(0)) revert InvalidAddress();
        blacklist[account] = true;
        emit AddedToBlacklist(account);
    }

    /**
     * @notice Lifts restriction from a previously blacklisted account.
     */
    function removeFromBlacklist(address account) external onlyRole(BLACKLIST_OPERATOR) {
        if (account == address(0)) revert InvalidAddress();
        blacklist[account] = false;
        emit RemovedFromBlacklist(account);
    }

    // ---------------------------------------------------------
    // Frontend Read Helpers
    // ---------------------------------------------------------

    /**
     * @notice Returns maximum allowed token supply.
     */
    function cap() external view returns (uint256) {
        return CAP;
    }

    /**
     * @notice Returns if an account is restricted (used by UI for immediate feedback).
     */
    function isBlacklisted(address account) external view returns (bool) {
        return blacklist[account];
    }

    // ---------------------------------------------------------
    // Internal Overrides
    // ---------------------------------------------------------

    /**
     * @dev Hook that intercepts all token transfers, mints, and burns.
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20) {
        if (blacklist[from]) revert AddressBlacklisted(from);
        if (blacklist[to]) revert AddressBlacklisted(to);

        // Verify CAP limit on minting
        if (from == address(0)) {
            uint256 projectedSupply = totalSupply() + amount;
            if (projectedSupply > CAP) {
                revert CapExceeded(projectedSupply, CAP);
            }
        }
        
        super._update(from, to, amount);
    }
}