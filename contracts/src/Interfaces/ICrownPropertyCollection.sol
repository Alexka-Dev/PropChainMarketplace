// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title ICrownPropertyCollection
 * @notice Interfaz para la colección de NFTs de títulos de propiedad ERC-721.
 */
interface ICrownPropertyCollection is IERC721 {
    event PropertyMinted(uint256 indexed tokenId, address indexed owner);

    function safeMint(address to) external returns (uint256);
}
