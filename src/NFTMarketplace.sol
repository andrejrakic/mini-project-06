// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC721} from "./vendor/@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "./vendor/@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTMarketplace is ReentrancyGuard {
  struct Sale {
    uint256 tokenId; //
    uint256 priceInEth; //
    address seller; // ─────────────╮
    uint48 expirationTimestamp; // ─╯
    address nftCollection; //
  }

  uint256 internal nonce;

  mapping(uint256 id => Sale sale) public sales;
  mapping(bytes32 commitHash => uint256 commitedEth) public commits;

  event Sell(
    uint256 indexed id,
    address nftCollection,
    uint256 tokenId,
    uint48 expirationTimestamp,
    uint256 priceInEth
  );
  event Buy(address nftCollection, uint256 tokenId, uint256 priceInEth, address buyer);
  event Cancelled(uint256 indexed id);

  function sell(address _nftCollection, uint256 _tokenId, uint40 _expirationTimestamp, uint216 _priceInEth) external {
    require(IERC721(_nftCollection).ownerOf(_tokenId) == msg.sender, "Only Owner Can Sell");
    require(IERC721(_nftCollection).getApproved(_tokenId) == address(this), "Not Approved For Selling");
    require(_expirationTimestamp > block.timestamp, "Must be in Future");

    uint256 id = nonce++;

    sales[id] = Sale({
      seller: msg.sender,
      nftCollection: _nftCollection,
      tokenId: _tokenId,
      expirationTimestamp: _expirationTimestamp,
      priceInEth: _priceInEth
    });

    emit Sell(id, _nftCollection, _tokenId, _expirationTimestamp, _priceInEth);
  }

  function cancel(uint256 id) external {
    Sale memory sale = sales[id];
    require(sale.nftCollection != address(0), "Invalid id");
    require(IERC721(sale.nftCollection).ownerOf(sale.tokenId) == msg.sender, "Only Owner Can Cancel");

    delete sales[id];

    emit Cancelled(id);
  }

  function buyCommitScheme(bytes32 _commitHash) external payable {
    require(commits[_commitHash] == 0, "Already commited");

    commits[_commitHash] = msg.value;
  }

  function buyRevealScheme(
    bytes32 _commitHash,
    uint256 _id,
    address _buyer,
    string memory _salt
  ) external nonReentrant {
    require(_commitHash == generateCommitHash(_id, _buyer, _salt), "Commit hash missmatch");

    uint256 commitedEth = commits[_commitHash];
    Sale memory sale = sales[_id];

    require(commitedEth > sale.priceInEth, "Insufficient amount");
    require(block.timestamp < sale.expirationTimestamp, "Sale expired");

    delete sales[_id];
    delete commits[_commitHash];

    IERC721(sale.nftCollection).safeTransferFrom(sale.seller, _buyer, sale.tokenId);

    (bool successSale, ) = sale.seller.call{value: sale.priceInEth}("");
    require(successSale, "Failed to transfer leftover");

    uint256 leftover = commitedEth - sale.priceInEth;

    (bool successLeftover, ) = _buyer.call{value: leftover}("");
    require(successLeftover, "Failed to transfer leftover");

    emit Buy(sale.nftCollection, sale.tokenId, sale.priceInEth, _buyer);
  }

  function cancelBuying(bytes32 _commitHash, uint256 _id, address _buyer, string memory _salt) external nonReentrant {
    require(_commitHash == generateCommitHash(_id, _buyer, _salt), "Commit hash missmatch");

    uint256 amountToWithdraw = commits[_commitHash];

    delete commits[_commitHash];

    (bool success, ) = _buyer.call{value: amountToWithdraw}("");
    require(success, "Failed to transfer ETH");
  }

  function generateCommitHash(uint256 _id, address _buyer, string memory _salt) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(_id, _buyer, _salt));
  }
}
