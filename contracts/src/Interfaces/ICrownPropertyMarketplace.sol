// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/**
 * @title ICrownPropertyMarketplace
 * @notice Interfaz para el mercado secundario PropChain Marketplace.
 */
interface ICrownPropertyMarketplace {
    struct Listing {
        address seller;
        address nftAddress;
        uint256 tokenId;
        uint256 amount;
        uint256 price;
        address payToken;
        bool isERC1155;
    }

    event PropertyListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 price,
        address payToken,
        bool isERC1155
    );

    event PropertySold(
        address indexed seller,
        address indexed buyer,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        address payToken,
        uint256 protocolFee,
        uint256 royaltyFee
    );

    event PropertyCanceled(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);

    function listProperty(
        address nftAddress_,
        uint256 tokenId_,
        uint256 amount_,
        uint256 price_,
        address payToken_,
        bool isERC1155_
    ) external payable;

    function buyProperty(address nftAddress_, uint256 tokenId_) external payable;

    function cancelListing(address nftAddress_, uint256 tokenId_) external;

    function getListing(address nftAddress_, uint256 tokenId_) external view returns (Listing memory);
}
