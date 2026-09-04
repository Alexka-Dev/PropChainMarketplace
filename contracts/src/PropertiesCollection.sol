// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title PropertiesCollection
 * @author BytePeak Technology
 * @notice Represents real estate title deeds as ERC721 NFTs.
 * @dev Adjusted for seamless Frontend integration (Wagmi/Viem) & Marketplace compatibility.
 */
contract PropertiesCollection is ERC721, Ownable {
    using Strings for uint256;

    // ---------------------------------------------------------
    // 1. Immutable & State Variables
    // ---------------------------------------------------------

    /// @notice Maximum supply of NFTs that can be minted in this collection.
    uint256 public immutable MAX_SUPPLY;

    /// @notice Auto-incrementing identifier for property tokens.
    uint256 public currentTokenId;

    /// @notice Root URI for metadata resolution (IPFS / Web3 Storage).
    string public baseUri;

    // ---------------------------------------------------------
    // 2. Events (Frontend Listening Optimizations)
    // ---------------------------------------------------------

    event PropertyMinted(address indexed to, uint256 indexed tokenId, string tokenURI);
    event BaseURIUpdated(string newBaseURI);

    // ---------------------------------------------------------
    // 3. Custom Errors
    // ---------------------------------------------------------

    error MaxSupplyReached();
    error InvalidRecipient();
    error ZeroAddress();

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory baseUri_
    ) ERC721(name_, symbol_) Ownable(msg.sender) {
        MAX_SUPPLY = maxSupply_;
        baseUri = baseUri_;
    }

    /**
     * @notice Allows updating base URI in case of IPFS updates.
     */
    function updateBaseURI(string calldata newBaseUri_) external onlyOwner {
        baseUri = newBaseUri_;
        emit BaseURIUpdated(newBaseUri_);
    }


    // ---------------------------------------------------------
    // External Minting Logic
    // ---------------------------------------------------------

    /**
     * @notice Mints a property deed directly to a seller/user wallet.
     * @param to Address of the property owner/seller.
     */
    function mintTo(address to) external onlyOwner returns (uint256) {
        if (to == address(0)) revert InvalidRecipient();
        if (currentTokenId == MAX_SUPPLY) revert MaxSupplyReached();

        uint256 newId = currentTokenId;
        unchecked {
            ++currentTokenId;
        }

        _safeMint(to, newId);

        emit PropertyMinted(to, newId, tokenURI(newId));
        return newId;
    }

        // ---------------------------------------------------------
    // Frontend Read Helpers (Useful for Wagmi hooks)
    // ---------------------------------------------------------

     /**
     * @notice Returns total minted properties so far.
     */
    function totalSupply() external view returns (uint256) {
        return currentTokenId;
    }


 
    /**
     * @notice Returns complete URI for a given token ID.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireOwned(tokenId);
        string memory base = _baseURI();
        return bytes(base).length > 0 ? string.concat(base, tokenId.toString(), ".json") : "";
    }


    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }



}