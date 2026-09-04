// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IComplianceRegistry {
    function isVerified(address account) external view returns (bool);
}

/**
 * @title PropChainMarketplace
 * @author BytePeak Technology
 * @notice Marketplace multimoneda y RWA con soporte para NFTs de propiedad (ERC-721) y fracciones de $100 (ERC-1155).
 * @dev Optimizado para producción con OpenZeppelin v5, verificación KYC on-chain y compatibilidad Wagmi/Next.js.
 */
contract PropChainMarketplace is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------
    // 1. Structs
    // ---------------------------------------------------------

    /**
     * @notice Estructura representativa de una publicación de propiedad o fracción.
     */
    struct Listing {
        address seller;
        address nftAddress;
        uint256 tokenId;
        uint256 amount; // Cantidad (1 para ERC721, N para fracciones ERC1155)
        uint256 price; // Precio total o unitario según la configuración de venta
        address payToken; // Token de pago (address(0) para ETH Nativo)
        bool isERC1155; // True si es un token fraccionado ERC-1155
    }

    // ---------------------------------------------------------
    // 2. Roles & Constants
    // ---------------------------------------------------------

    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    /// @dev Representa ETH nativo en el mapeo de tokens de pago
    address public constant ETH_ADDRESS = address(0);

    uint256 private constant BPS_DENOMINATOR = 10000;
    uint256 private constant MAX_FEE_BPS = 1000; // 10% máximo comisión protocolo

    // ---------------------------------------------------------
    // 3. State Variables
    // ---------------------------------------------------------

    /// @notice Registro KYC/AML obligatorio.
    IComplianceRegistry public complianceRegistry;

    /// @notice Comisión del protocolo en puntos básicos (100 BPS = 1%).
    uint256 public protocolFeeBps = 100;

    /// @notice Tasa de publicación requerida en ETH nativo para listar.
    uint256 public listingFee = 0.01 ether;

    /// @notice Dirección receptora de las comisiones recolectadas por la plataforma.
    address public feeRecipient;

    /// @notice Lista blanca de tokens aceptados: Token Address => Estado Habilitado.
    mapping(address => bool) public isAcceptedPaymentToken;

    /// @notice Mapeo de publicaciones activas: NFT Address => Token ID => Listing Structure.
    mapping(address => mapping(uint256 => Listing)) public listings;

    // ---------------------------------------------------------
    // 4. Events
    // ---------------------------------------------------------

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

    event ListingPriceUpdated(
        address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 newPrice
    );

    event PaymentTokenStatusUpdated(address indexed token, bool indexed status);
    event ListingFeeUpdated(uint256 indexed newFee);
    event FeeRecipientUpdated(address indexed newRecipient);
    event ProtocolFeeUpdated(uint256 indexed newFeeBps);
    event ComplianceRegistryUpdated(address indexed newRegistry);

    // ---------------------------------------------------------
    // 5. Custom Errors
    // ---------------------------------------------------------

    error PriceMustBeGreaterThanZero();
    error IncorrectListingFee();
    error NotNFTOwner();
    error NFTAlreadyListed();
    error NotListingOwner();
    error NFTNotListed();
    error IncorrectPaymentAmount();
    error TransferFailed();
    error MarketplaceNotApproved();
    error PaymentTokenNotAccepted();
    error InvalidAddress();
    error UserNotKYCVerified(address user);
    error InsufficientAmountAvailable();
    error FeeExceedsLimit();

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------

    /**
     * @param initialPropChainToken Dirección del token ERC20 nativo PropChainToken.
     * @param usdcAddress Dirección del contrato USDC.
     * @param usdtAddress Dirección del contrato USDT.
     * @param complianceRegistry_ Dirección del registro KYC.
     * @param admin_ Dirección del administrador del protocolo.
     */
    constructor(
        address initialPropChainToken,
        address usdcAddress,
        address usdtAddress,
        address complianceRegistry_,
        address admin_
    ) {
        if (initialPropChainToken == address(0) || complianceRegistry_ == address(0) || admin_ == address(0)) {
            revert InvalidAddress();
        }

        feeRecipient = admin_;
        complianceRegistry = IComplianceRegistry(complianceRegistry_);

        // Configuración de Roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(FEE_MANAGER_ROLE, admin_);

        // Whitelist de tokens de pago por defecto
        isAcceptedPaymentToken[ETH_ADDRESS] = true;
        isAcceptedPaymentToken[initialPropChainToken] = true;

        if (usdcAddress != address(0)) isAcceptedPaymentToken[usdcAddress] = true;
        if (usdtAddress != address(0)) isAcceptedPaymentToken[usdtAddress] = true;
    }

    // ---------------------------------------------------------
    // CORE MARKETPLACE LOGIC
    // ---------------------------------------------------------

    /**
     * @notice Publica un NFT de propiedad o participaciones de $100 especificando token de pago y precio.
     */
    function listProperty(
        address nftAddress_,
        uint256 tokenId_,
        uint256 amount_,
        uint256 price_,
        address payToken_,
        bool isERC1155_
    ) external payable nonReentrant {
        if (price_ == 0 || amount_ == 0) revert PriceMustBeGreaterThanZero();
        if (msg.value != listingFee) revert IncorrectListingFee();
        if (!isAcceptedPaymentToken[payToken_]) revert PaymentTokenNotAccepted();
        if (!complianceRegistry.isVerified(msg.sender)) revert UserNotKYCVerified(msg.sender);
        if (listings[nftAddress_][tokenId_].price != 0) revert NFTAlreadyListed();

        _validateNFTListing(nftAddress_, tokenId_, amount_, isERC1155_);

        listings[nftAddress_][tokenId_] = Listing({
            seller: msg.sender,
            nftAddress: nftAddress_,
            tokenId: tokenId_,
            amount: amount_,
            price: price_,
            payToken: payToken_,
            isERC1155: isERC1155_
        });

        if (msg.value > 0) {
            (bool success,) = feeRecipient.call{value: msg.value}("");
            if (!success) revert TransferFailed();
        }

        emit PropertyListed(msg.sender, nftAddress_, tokenId_, amount_, price_, payToken_, isERC1155_);
    }

    /**
     * @notice Cancela una publicación activa.
     */
    function cancelListing(address nftAddress_, uint256 tokenId_) external nonReentrant {
        Listing storage listedItem = listings[nftAddress_][tokenId_];
        if (listedItem.seller != msg.sender) revert NotListingOwner();

        delete listings[nftAddress_][tokenId_];

        emit PropertyCanceled(msg.sender, nftAddress_, tokenId_);
    }

    /**
     * @notice Actualiza el precio de una publicación existente.
     */
    function updateListingPrice(address nftAddress_, uint256 tokenId_, uint256 newPrice_) external {
        if (newPrice_ == 0) revert PriceMustBeGreaterThanZero();

        Listing storage listedItem = listings[nftAddress_][tokenId_];
        if (listedItem.seller != msg.sender) revert NotListingOwner();

        listedItem.price = newPrice_;

        emit ListingPriceUpdated(msg.sender, nftAddress_, tokenId_, newPrice_);
    }

    /**
     * @notice Ejecuta la compra de la propiedad o fracciones publicadas con soporte de regalías ERC-2981.
     */
    function buyProperty(address nftAddress_, uint256 tokenId_) external payable nonReentrant {
        if (!complianceRegistry.isVerified(msg.sender)) revert UserNotKYCVerified(msg.sender);

        Listing memory listedItem = listings[nftAddress_][tokenId_];
        if (listedItem.price == 0) revert NFTNotListed();

        // Elimina el slot antes de interacciones externas (Protección Reentrancia)
        delete listings[nftAddress_][tokenId_];

        uint256 protocolFee = (listedItem.price * protocolFeeBps) / BPS_DENOMINATOR;

        (address royaltyReceiver, uint256 royaltyFee) = _calculateRoyalty(nftAddress_, tokenId_, listedItem.price);
        uint256 sellerAmount = listedItem.price - protocolFee - royaltyFee;

        // Transferencia del activo NFT / ERC1155
        if (listedItem.isERC1155) {
            IERC1155(nftAddress_)
                .safeTransferFrom(listedItem.seller, msg.sender, listedItem.tokenId, listedItem.amount, "");
        } else {
            IERC721(nftAddress_).safeTransferFrom(listedItem.seller, msg.sender, listedItem.tokenId);
        }

        // Transferencia de fondos (ETH o ERC20)
        if (listedItem.payToken == ETH_ADDRESS) {
            _processETHPayment(
                listedItem.price, sellerAmount, protocolFee, royaltyFee, listedItem.seller, royaltyReceiver
            );
        } else {
            _processERC20Payment(
                listedItem.payToken, sellerAmount, protocolFee, royaltyFee, listedItem.seller, royaltyReceiver
            );
        }

        emit PropertySold(
            listedItem.seller,
            msg.sender,
            listedItem.nftAddress,
            listedItem.tokenId,
            listedItem.amount,
            listedItem.price,
            listedItem.payToken,
            protocolFee,
            royaltyFee
        );
    }

    // ---------------------------------------------------------
    // ADMIN FUNCTIONS & MANAGEMENT
    // ---------------------------------------------------------

    function setPaymentTokenStatus(address token_, bool status_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isAcceptedPaymentToken[token_] = status_;
        emit PaymentTokenStatusUpdated(token_, status_);
    }

    function updateListingFee(uint256 newFee_) external onlyRole(FEE_MANAGER_ROLE) {
        listingFee = newFee_;
        emit ListingFeeUpdated(newFee_);
    }

    function setFeeRecipient(address newRecipient_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRecipient_ == address(0)) revert InvalidAddress();
        feeRecipient = newRecipient_;
        emit FeeRecipientUpdated(newRecipient_);
    }

    function setProtocolFeeBps(uint256 newFeeBps_) external onlyRole(FEE_MANAGER_ROLE) {
        if (newFeeBps_ > MAX_FEE_BPS) revert FeeExceedsLimit();
        protocolFeeBps = newFeeBps_;
        emit ProtocolFeeUpdated(newFeeBps_);
    }

    function setComplianceRegistry(address newRegistry_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRegistry_ == address(0)) revert InvalidAddress();
        complianceRegistry = IComplianceRegistry(newRegistry_);
        emit ComplianceRegistryUpdated(newRegistry_);
    }

    // ---------------------------------------------------------
    // FRONTEND GETTERS (Wagmi Helpers)
    // ---------------------------------------------------------

    /**
     * @notice Función de vista para obtener los detalles de la publicación directamente en la interfaz UI.
     */
    function getListing(address nftAddress_, uint256 tokenId_) external view returns (Listing memory) {
        return listings[nftAddress_][tokenId_];
    }

    // ---------------------------------------------------------
    // INTERNAL HELPERS
    // ---------------------------------------------------------

    function _processETHPayment(
        uint256 totalPrice,
        uint256 sellerAmount,
        uint256 protocolFee,
        uint256 royaltyFee,
        address seller,
        address royaltyReceiver
    ) private {
        if (msg.value != totalPrice) revert IncorrectPaymentAmount();

        if (protocolFee > 0) {
            (bool feeSuccess,) = feeRecipient.call{value: protocolFee}("");
            if (!feeSuccess) revert TransferFailed();
        }

        if (royaltyFee > 0 && royaltyReceiver != address(0)) {
            (bool royaltySuccess,) = royaltyReceiver.call{value: royaltyFee}("");
            if (!royaltySuccess) revert TransferFailed();
        }

        (bool sellerSuccess,) = seller.call{value: sellerAmount}("");
        if (!sellerSuccess) revert TransferFailed();
    }

    function _processERC20Payment(
        address payToken,
        uint256 sellerAmount,
        uint256 protocolFee,
        uint256 royaltyFee,
        address seller,
        address royaltyReceiver
    ) private {
        if (msg.value != 0) revert IncorrectPaymentAmount();

        IERC20 token = IERC20(payToken);

        if (protocolFee > 0) {
            token.safeTransferFrom(msg.sender, feeRecipient, protocolFee);
        }

        if (royaltyFee > 0 && royaltyReceiver != address(0)) {
            token.safeTransferFrom(msg.sender, royaltyReceiver, royaltyFee);
        }

        token.safeTransferFrom(msg.sender, seller, sellerAmount);
    }

    function _validateNFTListing(address nftAddress, uint256 tokenId, uint256 amount, bool isERC1155) private view {
        if (isERC1155) {
            IERC1155 token1155 = IERC1155(nftAddress);
            if (token1155.balanceOf(msg.sender, tokenId) < amount) revert NotNFTOwner();
            if (!token1155.isApprovedForAll(msg.sender, address(this))) revert MarketplaceNotApproved();
        } else {
            IERC721 token721 = IERC721(nftAddress);
            if (token721.ownerOf(tokenId) != msg.sender) revert NotNFTOwner();
            bool isApproved =
                token721.isApprovedForAll(msg.sender, address(this)) || token721.getApproved(tokenId) == address(this);
            if (!isApproved) revert MarketplaceNotApproved();
        }
    }

    function _calculateRoyalty(address nftAddress, uint256 tokenId, uint256 price)
        private
        view
        returns (address receiver, uint256 royaltyFee)
    {
        if (IERC165(nftAddress).supportsInterface(type(IERC2981).interfaceId)) {
            (receiver, royaltyFee) = IERC2981(nftAddress).royaltyInfo(tokenId, price);
        }
    }
}
