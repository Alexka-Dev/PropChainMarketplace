// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Interfaz local mínima para Chainlink Price Feed (evita problemas de importación y remappings)
interface IAggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @dev Interfaz local mínima para verificar listas negras en el token nativo.
interface IBlacklistable {
    function isBlacklisted(address account) external view returns (bool);
}

/**
 * @title Presale
 * @author BytePeak Technology
 * @notice Manages token presale supporting ETH (via Chainlink Price Feed), USDT, and USDC.
 * @dev Fully compatible with SafeERC20, OpenZeppelin v5, and Wagmi frontend hooks.
 */
contract Presale is Ownable {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------
    // 1. Immutable & State Variables
    // ---------------------------------------------------------

    IERC20 public immutable SALE_TOKEN;
    IERC20 public immutable USDT_TOKEN;
    IERC20 public immutable USDC_TOKEN;
    IAggregatorV3Interface public immutable ETH_USD_PRICE_FEED;

    bool public paused;

    /// @notice Price of 1 CPT token in USD, expressed with 8 decimals (matches Chainlink precision).
    /// @dev Default: $0.50 USD per token -> 50,000,000 (0.50 * 10^8)
    uint256 public tokenPriceInUsd = 50_000_000;

    // ---------------------------------------------------------
    // 2. Events
    // ---------------------------------------------------------

    event TokensPurchased(
        address indexed buyer, address indexed assetAddress, uint256 indexed amountSpent, uint256 tokensAllocated
    );

    event SetPaused(bool indexed isPaused);
    event TokenPriceUpdated(uint256 indexed newTokenPriceInUsd);

    // ---------------------------------------------------------
    // 3. Custom Errors
    // ---------------------------------------------------------

    error PresalePaused();
    error InvalidAddress();
    error UnsupportedStablecoin();
    error InvalidAmount();
    error InsufficientContractBalance();
    error EmptyBalance();
    error ETHTransferFailed();
    error UserIsBlacklisted();
    error InvalidOraclePrice();
    error StaleOraclePrice();

    // ---------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------

    modifier whenNotPaused() {
        if (paused) revert PresalePaused();
        _;
    }

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------

    /**
     * @param saleToken_ Address of PropChainToken contract.
     * @param usdt_ Address of USDT contract.
     * @param usdc_ Address of USDC contract.
     * @param priceFeed_ Address of Chainlink ETH/USD Price Feed aggregator.
     */
    constructor(address saleToken_, address usdt_, address usdc_, address priceFeed_) Ownable(msg.sender) {
        if (saleToken_ == address(0)) revert InvalidAddress();
        if (usdt_ == address(0)) revert InvalidAddress();
        if (usdc_ == address(0)) revert InvalidAddress();
        if (priceFeed_ == address(0)) revert InvalidAddress();

        SALE_TOKEN = IERC20(saleToken_);
        USDT_TOKEN = IERC20(usdt_);
        USDC_TOKEN = IERC20(usdc_);
        ETH_USD_PRICE_FEED = IAggregatorV3Interface(priceFeed_);
    }

    // ---------------------------------------------------------
    // CORE PUBLIC / EXTERNAL FUNCTIONS
    // ---------------------------------------------------------

    /**
     * @notice Allows purchasing tokens using native ETH dynamically priced via Chainlink.
     */
    function buyWithETH() external payable whenNotPaused {
        uint256 amountSpent = msg.value;
        if (amountSpent == 0) revert InvalidAmount();

        // Check blacklist on token contract via local interface casting
        if (IBlacklistable(address(SALE_TOKEN)).isBlacklisted(msg.sender)) {
            revert UserIsBlacklisted();
        }

        uint256 tokensToAllocate = calculateEthPurchase(amountSpent);

        if (SALE_TOKEN.balanceOf(address(this)) < tokensToAllocate) {
            revert InsufficientContractBalance();
        }

        SALE_TOKEN.safeTransfer(msg.sender, tokensToAllocate);

        emit TokensPurchased(msg.sender, address(0), amountSpent, tokensToAllocate);
    }

    /**
     * @notice Allows purchasing tokens using USDT or USDC (6 decimals).
     * @param stablecoin Payment token address (USDT or USDC).
     * @param amount Amount of stablecoin sent by investor.
     */
    function buyWithStablecoin(address stablecoin, uint256 amount) external whenNotPaused {
        if (stablecoin != address(USDT_TOKEN) && stablecoin != address(USDC_TOKEN)) {
            revert UnsupportedStablecoin();
        }
        if (amount == 0) revert InvalidAmount();

        // Check blacklist on token contract via local interface casting
        if (IBlacklistable(address(SALE_TOKEN)).isBlacklisted(msg.sender)) {
            revert UserIsBlacklisted();
        }

        uint256 tokensToAllocate = calculateStablecoinPurchase(amount);

        if (SALE_TOKEN.balanceOf(address(this)) < tokensToAllocate) {
            revert InsufficientContractBalance();
        }

        IERC20(stablecoin).safeTransferFrom(msg.sender, address(this), amount);
        SALE_TOKEN.safeTransfer(msg.sender, tokensToAllocate);

        emit TokensPurchased(msg.sender, stablecoin, amount, tokensToAllocate);
    }

    // ---------------------------------------------------------
    // ADMIN FUNCTIONS
    // ---------------------------------------------------------

    /**
     * @notice Updates the target USD price per CPT token (for presale phases).
     * @param newTokenPriceInUsd_ Price in USD with 8 decimals (e.g., $1.00 USD = 100000000).
     */
    function setTokenPriceInUsd(uint256 newTokenPriceInUsd_) external onlyOwner {
        require(newTokenPriceInUsd_ > 0, InvalidAmount());
        tokenPriceInUsd = newTokenPriceInUsd_;
        emit TokenPriceUpdated(newTokenPriceInUsd_);
    }

    /**
     * @notice Pause or resume presale operations.
     * @param paused_ True to pause the presale, false to resume.
     */
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit SetPaused(paused_);
    }

    /**
     * @notice Emergency withdraw or sweep unsold tokens or accumulated funds.
     * @param asset Token contract address or address(0) for native ETH.
     */
    function emergencyWithdraw(address asset) external onlyOwner {
        if (asset == address(0)) {
            uint256 balance = address(this).balance;
            require(balance > 0, EmptyBalance());

            (bool success,) = payable(owner()).call{value: balance}("");
            require(success, ETHTransferFailed());
        } else {
            IERC20 token = IERC20(asset);
            uint256 tokenBalance = token.balanceOf(address(this));
            require(tokenBalance > 0, EmptyBalance());

            token.safeTransfer(owner(), tokenBalance);
        }
    }

    // ---------------------------------------------------------
    // ORACLE & CALCULATION HELPERS
    // ---------------------------------------------------------

    /**
     * @notice Fetches the latest ETH/USD price from Chainlink Price Feed.
     * @return Raw price from Chainlink (with 8 decimals precision, e.g., 3000 * 10^8 = $3,000.00).
     */
    function getLatestEthPrice() public view returns (uint256) {
        (uint80 roundId, int256 price,, uint256 updateAt, uint80 answeredInRound) = ETH_USD_PRICE_FEED.latestRoundData();
        require(price > 0, InvalidOraclePrice());

        // Uso de desigualdades estrictas (>) para optimización de gas
        require(updateAt != 0 && answeredInRound > roundId - 1, StaleOraclePrice());

        // Reemplazo de '<= 3 hours' por '< 3 hours + 1' (10801 segundos) para la regla gas-strict-inequalities
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp - updateAt < 3 hours + 1, StaleOraclePrice());

        // casting to 'uint256' is safe because price > 0 check is performed above
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(price);
    }

    /**
     * @notice Calculates how many CPT tokens an investor receives for a given ETH amount.
     * @param ethAmount Amount of ETH sent in wei (18 decimals).
     * @return Amount of CPT tokens allocated (18 decimals).
     */
    function calculateEthPurchase(uint256 ethAmount) public view returns (uint256) {
        if (ethAmount == 0) return 0;
        uint256 ethPriceInUsd = getLatestEthPrice(); // 8 decimals

        return (ethAmount * ethPriceInUsd) / tokenPriceInUsd;
    }

    /**
     * @notice Calculates how many CPT tokens an investor receives for a given Stablecoin amount.
     * @param stableAmount Amount of USDT/USDC (6 decimals).
     * @return Amount of CPT tokens allocated (18 decimals).
     */
    function calculateStablecoinPurchase(uint256 stableAmount) public view returns (uint256) {
        if (stableAmount == 0) return 0;

        // Scale 6 decimals to 8 decimals precision: stableAmount * 10^2
        uint256 stableInUsd8Decimals = stableAmount * 100;

        // CPT Tokens = (stableInUsd8Decimals [8 dec] * 1e18) / tokenPriceInUsd [8 dec]
        return (stableInUsd8Decimals * 1e18) / tokenPriceInUsd;
    }
}
