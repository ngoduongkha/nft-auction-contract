// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./UITToken1155.sol";
import "./UITToken721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract NFTMarketplace is ReentrancyGuard, ERC1155Holder, ERC721Holder {
  using Counters for Counters.Counter;
  Counters.Counter private _tokenIds;
  address owner;

  struct Bid {
    address bidder;
    uint256 bid;
    uint256 bidTime;
  }
  struct AuctionInfo {
    uint256 startAt;
    uint256 endAt;
    address highestBidder;
    uint256 highestBid;
    uint256 highestBidTime;
    uint256 startingPrice;
    Bid[] bids;
  }
  struct MarketItem {
    uint256 tokenId;
    address nftContract;
    address payable seller;
    address payable owner;
    uint256 price;
    bool sold;
    bool bidded;
    bool isMultiToken;
    AuctionInfo auctionInfo;
  }
  mapping(uint256 => MarketItem) private idMarketItemMapping;
  
  event MarketItemCreated(uint256 indexed tokenId, address indexed nftContract, address owner, bool isMultiToken);
  event MarketItemListed(uint256 indexed tokenId, address indexed nftContract, address owner, bool isMultiToken, uint256 price);
  event MarketItemCancelListed(uint256 indexed tokenId, address indexed nftContract, address owner, bool isMultiToken, uint256 price);
  event MarketItemAuctionListed(uint256 indexed tokenId, address indexed nftContract, address seller, bool isMultiToken, uint256 startingPrice, uint256 startTime, uint256 endTime);
  event MarketItemAuctionEnded(uint256 indexed tokenId, address indexed nftContract, address seller, bool isMultiToken, address highestBidder, uint256 highestBid, uint256 endTime);
  event MarketItemSold(uint256 indexed tokenId, address indexed nftContract, address seller, address buyer, uint256 price);
  event MarketItemBidded(uint256 indexed tokenId, address indexed nftContract, address seller, address bidder, uint256 bid, uint256 bidTime);
  event BidderWithdraw(uint256 indexed tokenId, address indexed nftContract, address seller, address bidder, uint256 balance);

  constructor() {
    owner = payable(msg.sender);
  }

  uint256 MINIMUM_AUCTION_TIME = 1800; // 30 Minutes
  uint256 listingPrice = 0.025 ether;

  /* Updates the listing price of the contract */
  function updateListingPrice(uint _listingPrice) external payable {
    require(owner == msg.sender, "Only marketplace owner can update listing price.");
    listingPrice = _listingPrice;
  }

  /* Returns the listing price of the contract */
  function getListingPrice() external view returns (uint256) {
    return listingPrice;
  }

  function createMarketItem(address nftContract, string memory tokenUri, bool isMultiToken) external payable {
    _tokenIds.increment();
    uint256 tokenId = _tokenIds.current();
    if (isMultiToken) {
      createNFT1155(tokenId, 1, tokenUri, nftContract); // Amount set to 1 as NFT
    } else {
      createNFT721(tokenId, tokenUri, nftContract);
    }
    idMarketItemMapping[tokenId].tokenId = tokenId;
    idMarketItemMapping[tokenId].nftContract = nftContract;
    idMarketItemMapping[tokenId].seller = payable(address(0));
    idMarketItemMapping[tokenId].owner = payable(msg.sender);
    idMarketItemMapping[tokenId].sold = true;
    idMarketItemMapping[tokenId].bidded = true;
    idMarketItemMapping[tokenId].isMultiToken = isMultiToken;
    emit MarketItemCreated(tokenId, nftContract, payable(msg.sender), isMultiToken);
  }

  function listAuctionItem(uint256 tokenId, uint256 startTime, uint256 endTime, uint256 startingPrice) external payable {
    require(msg.value == listingPrice, "Price must be equal to listing price");
    require(startingPrice > 0, "Starting price must be larger than 0");
    require(msg.sender == idMarketItemMapping[tokenId].owner, "Only owner can auction");
    require(idMarketItemMapping[tokenId].sold && idMarketItemMapping[tokenId].bidded, "NFT is on sale");
    require(block.timestamp < endTime, "Ended!");
    require(endTime - startTime > MINIMUM_AUCTION_TIME, "The auction time must be longer than 30 minutes!");
    idMarketItemMapping[tokenId].auctionInfo.startAt = startTime;
    idMarketItemMapping[tokenId].auctionInfo.endAt = endTime;
    idMarketItemMapping[tokenId].auctionInfo.highestBid = 0;
    idMarketItemMapping[tokenId].auctionInfo.highestBidder = address(0);
    idMarketItemMapping[tokenId].auctionInfo.highestBidTime = 0;
    idMarketItemMapping[tokenId].auctionInfo.startingPrice = startingPrice;
    delete idMarketItemMapping[tokenId].auctionInfo.bids;
    idMarketItemMapping[tokenId].bidded = false;
    idMarketItemMapping[tokenId].seller = payable(msg.sender);
    idMarketItemMapping[tokenId].owner = payable(address(this));
    transferToken(msg.sender, address(this), tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].isMultiToken);
    emit MarketItemAuctionListed(tokenId, idMarketItemMapping[tokenId].nftContract, msg.sender, idMarketItemMapping[tokenId].isMultiToken, startingPrice, startTime, endTime);
  }

  function listMarketItem(uint256 tokenId, uint256 price) external payable {
    require(msg.value >= listingPrice, "Price must be equal or higher than listing price");
    require(price > 0, "Price must be at least 1 wei");
    require(idMarketItemMapping[tokenId].owner == msg.sender, "Only owner can list item!");
    idMarketItemMapping[tokenId].price = price;
    idMarketItemMapping[tokenId].sold = false;
    idMarketItemMapping[tokenId].seller = payable(msg.sender);
    idMarketItemMapping[tokenId].owner = payable(address(this));
    transferToken(msg.sender, address(this), tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].isMultiToken);
    emit MarketItemListed(tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].owner, idMarketItemMapping[tokenId].isMultiToken, price);
  }

  function bid(uint256 tokenId) external payable {
    require(idMarketItemMapping[tokenId].seller != msg.sender, "You can't bid your item");
    require(idMarketItemMapping[tokenId].bidded == false, "Item isn't bidding");
    require(block.timestamp > idMarketItemMapping[tokenId].auctionInfo.startAt && block.timestamp < idMarketItemMapping[tokenId].auctionInfo.endAt, "Not in bid period!");
    require(msg.value > idMarketItemMapping[tokenId].auctionInfo.highestBid, "Must bid higher the highest bid!");
    if (idMarketItemMapping[tokenId].auctionInfo.highestBidder != address(0)) {
      Bid memory bidItem = Bid({bidder: idMarketItemMapping[tokenId].auctionInfo.highestBidder, bid: idMarketItemMapping[tokenId].auctionInfo.highestBid, bidTime: idMarketItemMapping[tokenId].auctionInfo.highestBidTime});
      idMarketItemMapping[tokenId].auctionInfo.bids.push(bidItem);
    }
    idMarketItemMapping[tokenId].auctionInfo.highestBid = msg.value;
    idMarketItemMapping[tokenId].auctionInfo.highestBidder = msg.sender;
    idMarketItemMapping[tokenId].auctionInfo.highestBidTime = block.timestamp;
    emit MarketItemBidded(tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].seller, msg.sender, msg.value, block.timestamp);
  }

  function withdrawBid(uint256 tokenId) external payable nonReentrant {
    uint256 balance = 0;
    for (uint i = 0; i < idMarketItemMapping[tokenId].auctionInfo.bids.length; i++) {
      if (idMarketItemMapping[tokenId].auctionInfo.bids[i].bidder == msg.sender) {
        balance += idMarketItemMapping[tokenId].auctionInfo.bids[i].bid;
        idMarketItemMapping[tokenId].auctionInfo.bids[i].bid = 0;
      }
    }
    require(balance > 0, "You haven't bidded yet!");
    payable(msg.sender).transfer(balance);
    emit BidderWithdraw(tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].seller, msg.sender, balance);
  }

  function endAuction(uint256 tokenId) external payable nonReentrant {
    require(block.timestamp > idMarketItemMapping[tokenId].auctionInfo.endAt, "Auction is still ongoing!");
    require(!idMarketItemMapping[tokenId].bidded, "Auction already ended!");
    if (idMarketItemMapping[tokenId].auctionInfo.highestBidder != address(0)) { // Transfer token to winner
        for (uint i = 0; i < idMarketItemMapping[tokenId].auctionInfo.bids.length; i++) {
          if (idMarketItemMapping[tokenId].auctionInfo.bids[i].bid > 0) {
            payable(idMarketItemMapping[tokenId].auctionInfo.bids[i].bidder).transfer(idMarketItemMapping[tokenId].auctionInfo.bids[i].bid);
          }
        }
        payable(idMarketItemMapping[tokenId].seller).transfer(idMarketItemMapping[tokenId].auctionInfo.highestBid);
        idMarketItemMapping[tokenId].owner = payable(idMarketItemMapping[tokenId].auctionInfo.highestBidder);
        transferToken(address(this), idMarketItemMapping[tokenId].auctionInfo.highestBidder, tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].isMultiToken);
    } else { // Transfer token to seller
        transferToken(address(this), idMarketItemMapping[tokenId].seller, tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].isMultiToken);
        idMarketItemMapping[tokenId].owner = payable(idMarketItemMapping[tokenId].seller);
    }
    payable(idMarketItemMapping[tokenId].seller).transfer(listingPrice);
    idMarketItemMapping[tokenId].seller = payable(address(0));
    idMarketItemMapping[tokenId].bidded = true;
    emit MarketItemAuctionEnded(tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].owner, idMarketItemMapping[tokenId].isMultiToken, idMarketItemMapping[tokenId].auctionInfo.highestBidder, idMarketItemMapping[tokenId].auctionInfo.highestBid, block.timestamp);
  }
  
  function createMarketSale(uint256 tokenId) external payable nonReentrant {
    address payable seller = idMarketItemMapping[tokenId].seller;
    require(idMarketItemMapping[tokenId].sold == false, "Item isn't on sale");
    require(msg.value == idMarketItemMapping[tokenId].price, "Buyer must transfer equal price of item");
    payable(idMarketItemMapping[tokenId].seller).transfer(msg.value);
    payable(idMarketItemMapping[tokenId].seller).transfer(listingPrice);
    idMarketItemMapping[tokenId].owner = payable(msg.sender);
    idMarketItemMapping[tokenId].seller = payable(address(0));
    idMarketItemMapping[tokenId].sold = true;
    transferToken(address(this), msg.sender, tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].isMultiToken);
    emit MarketItemSold(tokenId, idMarketItemMapping[tokenId].nftContract, seller, msg.sender, idMarketItemMapping[tokenId].price);
  }

  function cancelListingItem(uint256 tokenId) external payable {
    require(msg.sender == idMarketItemMapping[tokenId].seller, "Only seller can cancel listing!");
    require(idMarketItemMapping[tokenId].sold == false || idMarketItemMapping[tokenId].bidded == false, "Only listed item can cancel listing!");
    if (idMarketItemMapping[tokenId].bidded == false) {
      require(idMarketItemMapping[tokenId].auctionInfo.endAt > block.timestamp, "Cannot cancel when auction already ended!");
      if (idMarketItemMapping[tokenId].auctionInfo.highestBidder != address(0)) { // Transfer token to winner
          for (uint i = 0; i < idMarketItemMapping[tokenId].auctionInfo.bids.length; i++) {
            if (idMarketItemMapping[tokenId].auctionInfo.bids[i].bid > 0) {
              payable(idMarketItemMapping[tokenId].auctionInfo.bids[i].bidder).transfer(idMarketItemMapping[tokenId].auctionInfo.bids[i].bid);
            }
          }
          payable(idMarketItemMapping[tokenId].auctionInfo.highestBidder).transfer(idMarketItemMapping[tokenId].auctionInfo.highestBid);
      }
      idMarketItemMapping[tokenId].bidded = true;
    } else {
      idMarketItemMapping[tokenId].sold = true;
    }
    idMarketItemMapping[tokenId].owner = payable(msg.sender);
    idMarketItemMapping[tokenId].seller = payable(address(0));
    transferToken(address(this), msg.sender, tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].isMultiToken);
    emit MarketItemCancelListed(tokenId, idMarketItemMapping[tokenId].nftContract, idMarketItemMapping[tokenId].owner, idMarketItemMapping[tokenId].isMultiToken, idMarketItemMapping[tokenId].price);
  }

  // function fetchMarketItem(uint256 _id) external view returns(MarketItem memory){
  //   return idMarketItemMapping[_id];
  // }

  // function fetchAllNFTs(uint256 cursor, uint256 howMany) external view returns (MarketItem[] memory items, uint256 newCursor, uint256 totalItemCount) {
  //   uint _totalItemCount = _tokenIds.current();
  //   if (cursor >= _totalItemCount) {
  //     MarketItem[] memory _emptyItem = new MarketItem[](0);
  //     return (_emptyItem, cursor, _totalItemCount);
  //   }
  //   uint256 length = howMany;
  //   if (length > _totalItemCount - cursor) {
  //     length = _totalItemCount - cursor;
  //   }

  //   MarketItem[] memory _items = new MarketItem[](length);
  //   for (uint i = cursor; i < length + cursor; i++) {
  //     MarketItem storage currentItem = idMarketItemMapping[i+1];
  //     _items[i] = currentItem;
  //   }
  //   return (_items, cursor + length, _totalItemCount);
  // }

  // /* Returns all available market items */
  // function fetchAvailableMarketItems() public view returns (MarketItem[] memory items) {
  //   uint totalItemCount = _tokenIds.current();
  //   uint itemCount = 0;
  //   uint currentIndex = 0;

  //   for (uint i = 0; i < totalItemCount; i++) {
  //     if (idMarketItemMapping[i + 1].sold == false || (idMarketItemMapping[i + 1].bidded == false && idMarketItemMapping[i + 1].auctionInfo.endAt > block.timestamp && idMarketItemMapping[i + 1].auctionInfo.startAt < block.timestamp)) {
  //       itemCount += 1;
  //     }
  //   }

  //   MarketItem[] memory _items = new MarketItem[](itemCount);
  //   for (uint i = 0; i < totalItemCount; i++) {
  //     if (idMarketItemMapping[i + 1].sold == false || (idMarketItemMapping[i + 1].bidded == false && idMarketItemMapping[i + 1].auctionInfo.endAt > block.timestamp && idMarketItemMapping[i + 1].auctionInfo.startAt < block.timestamp)) {
  //       uint currentId = i + 1;
  //       MarketItem storage currentItem = idMarketItemMapping[currentId];
  //       _items[currentIndex] = currentItem;
  //       currentIndex += 1;
  //     }
  //   }
  //   return _items;
  // }

  // /* Returns all available bidded auction */
  // function fetchAvailableBiddedAuction() public view returns (MarketItem[] memory items) {
  //   uint totalItemCount = _tokenIds.current();
  //   uint itemCount = 0;
  //   uint currentIndex = 0;

  //   for (uint i = 0; i < totalItemCount; i++) {
  //     if (idMarketItemMapping[i + 1].sold == true && idMarketItemMapping[i + 1].bidded == false && idMarketItemMapping[i + 1].auctionInfo.startAt < block.timestamp && idMarketItemMapping[i + 1].auctionInfo.highestBidder != address(0)) {
  //       if (idMarketItemMapping[i + 1].auctionInfo.highestBidder == msg.sender) {
  //         itemCount += 1;
  //       } else {
  //         Bid[] memory bids = idMarketItemMapping[i + 1].auctionInfo.bids;
  //         for (uint j = 0; j < bids.length; j++) {
  //           if (bids[j].bidder == msg.sender) {
  //             itemCount += 1;
  //             break;
  //           }
  //         }
  //       }
  //     }
  //   }

  //   MarketItem[] memory _items = new MarketItem[](itemCount);
  //   for (uint i = 0; i < totalItemCount; i++) {
  //     if (idMarketItemMapping[i + 1].sold == true && idMarketItemMapping[i + 1].bidded == false && idMarketItemMapping[i + 1].auctionInfo.startAt < block.timestamp && idMarketItemMapping[i + 1].auctionInfo.highestBidder != address(0)) {
  //       if (idMarketItemMapping[i + 1].auctionInfo.highestBidder == msg.sender) {
  //         uint currentId = i + 1;
  //         MarketItem storage currentItem = idMarketItemMapping[currentId];
  //         _items[currentIndex] = currentItem;
  //         currentIndex += 1;
  //       } else {
  //         Bid[] memory bids = idMarketItemMapping[i + 1].auctionInfo.bids;
  //         for (uint j = 0; j < bids.length; j++) {
  //           if (bids[j].bidder == msg.sender) {
  //             uint currentId = i + 1;
  //             MarketItem storage currentItem = idMarketItemMapping[currentId];
  //             _items[currentIndex] = currentItem;
  //             currentIndex += 1;
  //             break;
  //           }
  //         }
  //       }
  //     }
  //   }
  //   return _items;
  // }

  // /* Returns only items that a user has purchased */
  // function fetchMyNFTs() public view returns (MarketItem[] memory items) {
  //   uint totalItemCount = _tokenIds.current();
  //     uint itemCount = 0;
  //     uint currentIndex = 0;

  //     for (uint i = 0; i < totalItemCount; i++) {
  //       if (idMarketItemMapping[i + 1].owner == msg.sender) {
  //         itemCount += 1;
  //       }
  //     }

  //     MarketItem[] memory _items = new MarketItem[](itemCount);
  //     for (uint i = 0; i < totalItemCount; i++) {
  //       if (idMarketItemMapping[i + 1].owner == msg.sender) {
  //         uint currentId = i + 1;
  //         MarketItem storage currentItem = idMarketItemMapping[currentId];
  //         _items[currentIndex] = currentItem;
  //         currentIndex += 1;
  //       }
  //     }
  //     return _items;
  // }

  // /* Returns only items a user has listed */
  // function fetchItemsListed() public view returns (MarketItem[] memory items) {
  //   uint totalItemCount = _tokenIds.current();
  //     uint itemCount = 0;
  //     uint currentIndex = 0;

  //     for (uint i = 0; i < totalItemCount; i++) {
  //       if (idMarketItemMapping[i + 1].seller == msg.sender) {
  //         itemCount += 1;
  //       }
  //     }

  //     MarketItem[] memory _items = new MarketItem[](itemCount);
  //     for (uint i = 0; i < totalItemCount; i++) {
  //       if (idMarketItemMapping[i + 1].seller == msg.sender) {
  //         uint currentId = i + 1;
  //         MarketItem storage currentItem = idMarketItemMapping[currentId];
  //         _items[currentIndex] = currentItem;
  //         currentIndex += 1;
  //       }
  //     }
  //     return _items;
  // }

  /**ERC1155 functionality ***********************************************/
  function get1155TokenURI(uint256 _tokenId, address _collection) public view returns(string memory){
    return UITToken1155(_collection).getTokenURI(_tokenId);
  }
  function createNFT1155(uint256 _tokenId, uint256 _amount, string memory _tokenUri, address _collection) private {
    UITToken1155(_collection).mintNFT(msg.sender, _tokenId, _amount, _tokenUri);
  }

  /**ERC721 functionality *************************************************/
  function createNFT721(uint256 _tokenId, string memory uri, address _collection) private {
    UITToken721(_collection).mintNFT(msg.sender, _tokenId, uri);
  }

  function get721TokenURI(uint256 _tokenId, address _collection) public view returns(string memory) {
    return UITToken721(_collection).getTokenUri(_tokenId);
  }

  function transferToken(address _owner, address _receiver, uint _tokenId, address _nftContract, bool isMultiToken) private {
    if (isMultiToken) {
      IERC1155(_nftContract).safeTransferFrom(_owner, _receiver, _tokenId, 1, '[]');
    } else {
      IERC721(_nftContract).safeTransferFrom(_owner, _receiver, _tokenId);
    }
  }
}