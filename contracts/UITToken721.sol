// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract UITToken721 is ERC721URIStorage, Ownable {
    address parentAddress;
    uint256[] tokensIdsCreated;
    string private collectionName;
    string private collectionSymbol;
    struct NFTToken{
        uint256 id;
        string uri;
    }

    mapping (uint256 => NFTToken) idToNFTMapping;
    
    constructor(string memory _name, string memory _symbol, address _parentAddress) ERC721(_name, _symbol) {
        parentAddress = _parentAddress;
        collectionName = _name;
        collectionSymbol = _symbol;
    }

    function setParentApproval() public {
        setApprovalForAll(parentAddress, true);
    }

    function name() public view override returns(string memory) {
        return collectionName;
    }

    function symbol() public view override returns(string memory) {
        return collectionSymbol;
    }

    function setName(string memory _name) public onlyOwner {
        collectionName = _name;
    }

    function setSymbol(string memory _symbol) public onlyOwner {
        collectionSymbol = _symbol;
    }

    function mintNFT(address _owner, uint256 _id, string memory _tokenUri) public {
       // using erc 721 to create NFT
       // mint will create NFT and send it to the address. 
       _mint(_owner, _id); 
       _setTokenURI(_id, _tokenUri);
       tokensIdsCreated.push(_id);
       idToNFTMapping[_id].id = _id;
       idToNFTMapping[_id].uri = _tokenUri;
    }

    function getTokenUri(uint256 tokenId) public view returns(string memory){
        return idToNFTMapping[tokenId].uri;
    }

    //get tokens totalnumber. 
    function getTokenCount() public view returns (uint256) {
        return tokensIdsCreated.length;
    }
    //returns the array of all tokenids. 
    function getTokenIds() public  view returns (uint256[] memory) {
        return tokensIdsCreated;
    }
    
}