// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {PropertiesCollection} from "@src/PropertiesCollection.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract PropertiesCollectionTest is Test {
    PropertiesCollection public collection;

    // Accounts
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    // Initial Params
    string public constant NAME = "Real Estate Collection";
    string public constant SYMBOL = "REC";
    uint256 public constant MAX_SUPPLY = 5;
    string public constant BASE_URI = "ipfs://QmTest123/";

    // Events (re-declared for vm.expectEmit)
    event PropertyMinted(address indexed to, uint256 indexed tokenId, string tokenURI);
    event BaseURIUpdated(string newBaseURI);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public {
        vm.prank(owner);
        collection = new PropertiesCollection(NAME, SYMBOL, MAX_SUPPLY, BASE_URI);
    }

    // ---------------------------------------------------------
    // 1. Constructor & Initial State Tests
    // ---------------------------------------------------------

    function test_InitialState() public view {
        assertEq(collection.name(), NAME);
        assertEq(collection.symbol(), SYMBOL);
        assertEq(collection.MAX_SUPPLY(), MAX_SUPPLY);
        assertEq(collection.baseUri(), BASE_URI);
        assertEq(collection.currentTokenId(), 0);
        assertEq(collection.totalSupply(), 0);
        assertEq(collection.owner(), owner);
    }

    // ---------------------------------------------------------
    // 2. updateBaseURI Tests
    // ---------------------------------------------------------

    function test_UpdateBaseURI_Success() public {
        string memory newBaseUri = "https://api.bytepeak.tech/metadata/";

        vm.expectEmit(true, true, true, true);
        emit BaseURIUpdated(newBaseUri);

        vm.prank(owner);
        collection.updateBaseURI(newBaseUri);

        assertEq(collection.baseUri(), newBaseUri);
    }

    function test_UpdateBaseURI_RevertsIfNotOwner() public {
        string memory newBaseUri = "https://api.bytepeak.tech/metadata/";

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));

        vm.prank(user1);
        collection.updateBaseURI(newBaseUri);
    }

    // ---------------------------------------------------------
    // 3. mintTo Tests
    // ---------------------------------------------------------

    function test_MintTo_Success() public {
        string memory expectedTokenURI = string.concat(BASE_URI, "0.json");

        // Mint event & ERC721 Transfer event verification
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), user1, 0);

        vm.expectEmit(true, true, true, true);
        emit PropertyMinted(user1, 0, expectedTokenURI);

        vm.prank(owner);
        uint256 mintedId = collection.mintTo(user1);

        assertEq(mintedId, 0);
        assertEq(collection.currentTokenId(), 1);
        assertEq(collection.totalSupply(), 1);
        assertEq(collection.ownerOf(0), user1);
        assertEq(collection.balanceOf(user1), 1);
    }

    function test_MintTo_RevertsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));

        vm.prank(user1);
        collection.mintTo(user2);
    }

    function test_MintTo_RevertsIfZeroAddress() public {
        vm.expectRevert(PropertiesCollection.InvalidRecipient.selector);

        vm.prank(owner);
        collection.mintTo(address(0));
    }

    function test_MintTo_RevertsIfMaxSupplyReached() public {
        vm.startPrank(owner);

        // Mint up to MAX_SUPPLY (0 to 4)
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            collection.mintTo(user1);
        }

        assertEq(collection.totalSupply(), MAX_SUPPLY);

        // Attempting to mint 1 more beyond MAX_SUPPLY
        vm.expectRevert(PropertiesCollection.MaxSupplyReached.selector);
        collection.mintTo(user1);

        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // 4. tokenURI Tests
    // ---------------------------------------------------------

    function test_TokenURI_Success() public {
        vm.prank(owner);
        collection.mintTo(user1);

        string memory uri = collection.tokenURI(0);
        assertEq(uri, "ipfs://QmTest123/0.json");
    }

    function test_TokenURI_EmptyBaseURI() public {
        // Deploy collection with empty Base URI to test branch coverage
        vm.prank(owner);
        PropertiesCollection emptyUriCollection = new PropertiesCollection(NAME, SYMBOL, MAX_SUPPLY, "");

        vm.prank(owner);
        emptyUriCollection.mintTo(user1);

        string memory uri = emptyUriCollection.tokenURI(0);
        assertEq(uri, "");
    }

    function test_TokenURI_RevertsIfNonExistentToken() public {
        // OpenZeppelin ERC721 NonexistentToken error
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 999));
        collection.tokenURI(999);
    }
}