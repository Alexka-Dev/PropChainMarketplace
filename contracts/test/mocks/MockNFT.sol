// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.29;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract MockNFT is ERC721, IERC2981 {
    address private _royaltyReceiver;
    uint96 private _royaltyBps; // Ej: 250 = 2.5%

    constructor() ERC721("Mock Property NFT", "MPROP") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function setRoyalty(address receiver, uint96 bps) external {
        _royaltyReceiver = receiver;
        _royaltyBps = bps;
    }

    // Soporte para ERC-2981 (Regalías)
    function royaltyInfo(uint256, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = _royaltyReceiver;
        royaltyAmount = (salePrice * _royaltyBps) / 10000;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}

contract MockERC1155 is ERC1155 {
    constructor() ERC1155("https://api.propchain.com/metadata/{id}.json") {}

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}
