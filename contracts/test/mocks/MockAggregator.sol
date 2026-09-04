// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.29;

import {IAggregator} from "@interfaces/IAggregator.sol";

contract MockAggregator is IAggregator {
    uint8 private immutable i_decimals;
    int256 private s_price;

    // Constructor principal (2 argumentos)
    constructor(uint8 decimals_, int256 initialPrice) {
        i_decimals = decimals_;
        s_price = initialPrice;
    }

    function decimals() external view returns (uint8) {
        return i_decimals;
    }

    /// @notice Permite cambiar el precio simulado en los tests
    function setPrice(int256 price) external {
        s_price = price;
    }

    /// @notice Implementación de la interfaz para que Presale la pueda consultar
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, s_price, block.timestamp, block.timestamp, 1);
    }
}