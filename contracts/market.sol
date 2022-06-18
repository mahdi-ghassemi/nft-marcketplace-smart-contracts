// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev The contract has an owner address, and provides basic authorization control whitch
 * simplifies the implementation of user permissions. This contract is based on the source code at:
 * https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/ownership/Ownable.sol
 */
contract Ownable {
    /**
     * @dev Error constants.
     */
    string public constant NOT_CURRENT_OWNER = "018001";
    string public constant CANNOT_TRANSFER_TO_ZERO_ADDRESS = "018002";

    /**
     * @dev Current owner address.
     */
    address public owner;

    /**
     * @dev An event which is triggered when the owner is changed.
     * @param previousOwner The address of the previous owner.
     * @param newOwner The address of the new owner.
     */
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev The constructor sets the original `owner` of the contract to the sender account.
     */
    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, NOT_CURRENT_OWNER);
        _;
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param _newOwner The address to transfer ownership to.
     */
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), CANNOT_TRANSFER_TO_ZERO_ADDRESS);
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }
}


/**
 * @notice INFT_TOKEN is some needed function from our NFT token smrat contract (nft_token.sol) interface.
 */
interface INFT_TOKEN {
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external;

    function ownerOf(uint256 _tokenId) external view returns (address);

    function getApproved(uint256 _tokenId) external view returns (address);

    function getTokenCreator(uint256 _tokenId) external view returns (address);
}

/**
* @title This is the main marketplace smart contract.
* @author Mahdi Ghasemi
* @dev 'nftTokenContractAddress' is a public address variable which refers to the our NFT token smart contract address
* @dev 'platformFee' is a public uint256 variable which determines the amount of the platform fee for transactions.
        This varible should be 'wei' base. So for examle if:
        Our platform fee is 2.5% , then 'platformFee' should be 2500000000000000000 wei
        Our platform fee is 2% , then 'platformFee' should be 2000000000000000000 wei
* @dev  'platformBalance' is a public uint256 variable which maintains the balance of fees received by the platform.
         This balance ensures that the contract owner cannot withdraw more than the amount of available commissions
         from the smart contract balance.
 */
contract Marketplace is Ownable {   
    address public nftTokenContractAddress;
    uint256 public platformFee;
    uint256 public platformBalance;

    /** @dev Events definition  */    

    event SetOffer(uint256 _tokenId, uint256 _price);
    event CancelOffer(uint256 _tokenId);
    event OfferUpdated(uint256 _tokenId, uint256 _price);

    event BidAccepted(uint256 _tokenId, uint256 _price);
    event BidCanceled(uint256 _tokenId);
    event BidReject(uint256 _tokenId, uint256 _price);
    
    event BuyDone(uint256 _tokenId, uint256 _price);

    event DepositSucceed(address _sender, uint256 _value);
    event WithdrawingSucceed(address _sender,uint256 _amount);

    /** @dev Struct definition */
    struct Offer {
        uint256 tokenId;
        address payable seller;
        uint256 price;
        uint256 sold_price;
        bool sold; 
    }

    struct Creator {
        uint256 tokenId;
        address payable creator;
        uint256 royalty;
    }

    struct Bid {
        uint256 tokenId;
        address payable bidOwner;
        uint256 offerPrice;
        bool active;
    }

    Offer[] offers;
    Creator[] creators;
    Bid[] bids;

    /** @dev Mapping definition*/
    mapping(uint256 => Offer) tokenIdToOffer;
    mapping(uint256 => uint256) tokenIdToOfferIndex;
    mapping(address => uint256) private _balances;
    mapping(uint256 => Creator) tokenIdToCreator;
    mapping(uint256 => uint256) tokenIdToCreatorIndex;
    mapping(uint256 => Bid) tokenIdToBid;
    mapping(uint256 => uint256) tokenIdToBidIndex;

    
    /** @param _nftTokenContractAddress NFT token smart contract address
    *   @dev We set a null offer at the first item in offer array   
    */
    constructor(address _nftTokenContractAddress) {
        nftTokenContractAddress = _nftTokenContractAddress;
        Offer memory _offer = Offer({
            tokenId: 0,
            seller: payable(address(this)),
            price: 0,
            sold_price: 0,
            sold: true
        });
        tokenIdToOffer[0] = _offer;
        offers.push(_offer);
        uint256 index = offers.length - 1;
        tokenIdToOfferIndex[0] = index;
    }

    /** @dev Setting our NFT token smart contract address by smart contract owner if it's changed after deploy
        @param  _nftTokenContractAddress NFT token smart contract address
        @return true if it's executed successfully    
    */
    function setNftTokenContractAddress(address _nftTokenContractAddress) public onlyOwner returns (bool) {
        nftTokenContractAddress = _nftTokenContractAddress;
        return true;
    }

     /** @dev Setting marketplace platform fee by smart contract owner
        @param  _platformFee Platform fee percent
        @return true if it's executed successfully    

        @notice _platformFee percent must be on wei unit
    */
    function setPlatformFee(uint256 _platformFee) public onlyOwner returns (bool) {
        platformFee = _platformFee;
        return true;
    }

    /** @dev Returning the an NFT owner
        @param _tokenId NFT token id
        @return address The NFT owner address    
    */
    function getNftOwner(uint256 _tokenId) public view returns (address) {
        return INFT_TOKEN(nftTokenContractAddress).ownerOf(_tokenId);
    }

    /** @dev Returning the an NFT creator
        @param _tokenId NFT token id
        @return address The NFT creator address     
    */
    function getNftCreator(uint256 _tokenId) public view returns (address) {
        return INFT_TOKEN(nftTokenContractAddress).getTokenCreator(_tokenId);
    }

    /** @dev Getting NFT creator array 
        @param _tokenId NFT token id
        @return Creator NFT Creator info if exists        
     */
    function getCreatorInfo(uint256 _tokenId) public view returns (Creator memory) {
        Creator storage _creator = creators[tokenIdToCreatorIndex[_tokenId]];
        return _creator;
    }

    /** @dev Setting a new sale offer by NFT owner only
        @param _tokenId NFT token id
        @param _price NFT token sale price
        @param _royalty NFT token royalty
        @return true if it's executed successfully

        @notice The NFT should be approved by owner before setting the sale offer
        @notice Royalty only can set when the NFT owner is creator. So the royalty only setting when the NFT
                creator put sale offer. After that, NFT creator and next owners can't to change it.
        @dev '_royalty' is aa uint256 variable which determines the percent of the creator royalty.
              This varible should be 'wei' base. So for examle if:
              Creator royalty is 10% , then '_royalty' should be 10000000000000000000 wei
              Creator royalty is 5.5% , then '_royalty' should be 5500000000000000000 wei                  
    */
    function addOffer(uint256 _tokenId, uint256 _price, uint256 _royalty) public returns (bool) {
        require(_price > 0, "Price must be greater than zero");
        require(offers[tokenIdToOfferIndex[_tokenId]].price == 0,"Offer duplicated");
        require(getNftOwner(_tokenId) == msg.sender, "You are not NFT owner");
        require(INFT_TOKEN(nftTokenContractAddress).getApproved(_tokenId) == address(this),"NFT must be approved");
        Offer memory _offer = Offer({
            tokenId: _tokenId,
            seller: payable(msg.sender),
            price: _price,
            sold_price: 0,
            sold: false
        });

        tokenIdToOffer[_tokenId] = _offer;
        offers.push(_offer);
        uint256 index = offers.length - 1;
        tokenIdToOfferIndex[_tokenId] = index;

        address _nftCreator = getNftCreator(_tokenId);
        if (msg.sender == _nftCreator && _royalty > 0) {
            Creator memory _creator = Creator({
                tokenId: _tokenId,
                creator: payable(msg.sender),
                royalty: _royalty
            });
            tokenIdToCreator[_tokenId] = _creator;
            creators.push(_creator);
            uint256 _index = creators.length - 1;
            tokenIdToCreatorIndex[_tokenId] = _index;
        }
        emit SetOffer(_tokenId, _price);
        return true;
    }

    
    /** @dev Setting a new bid by client
        @param _tokenId NFT token id
        @param _price Proposed price by client
        @return true if it's executed successfully

        @notice Proposed price must be greater than zero
        @notice NFT token id must be exists
        @notice The NFT owner can not bid on its own NFT 

        @dev Client has to deposit the proposed price in smart contract. If NFT owner reject the bid,
             client can withdraw the deposited amount from smart contract
    */
    function addBid(uint256 _tokenId, uint256 _price) public payable returns (bool) {
        require(_price > 0, "Price must be greater than zero");
        require(msg.value == _price);
        require(INFT_TOKEN(nftTokenContractAddress).ownerOf(_tokenId) != address(0),"NFT must be exists");
        _balances[msg.sender] += _price;
        if (bids[tokenIdToBidIndex[_tokenId]].bidOwner == msg.sender && bids[tokenIdToBidIndex[_tokenId]].active == true ) {
            emit BidReject(_tokenId, _price);
            return false;
        } else {
            Bid memory _bid = Bid({
                tokenId: _tokenId,
                bidOwner: payable(msg.sender),
                offerPrice: _price,
                active: true
            });

            tokenIdToBid[_tokenId] = _bid;
            bids.push(_bid);
            uint256 index = bids.length - 1;
            tokenIdToBidIndex[_tokenId] = index;
            emit BidAccepted(_tokenId, _price);
            return true;
        }
    }

    /** @dev Canceling a bid by bid owner
        @param _tokenId NFT token id       
        @return true if it's executed successfully

        @notice Bid must be active
        @notice The bid owner can cancel own bid 

        @dev Client can withdraw the deposited amount from smart contract
    */
    function cancelBid(uint256 _tokenId) public returns (bool) {
        require(bids[tokenIdToBidIndex[_tokenId]].bidOwner == msg.sender,"You don't have permissions");
        require(bids[tokenIdToBidIndex[_tokenId]].active == true,"Bid must be active");

        delete bids[tokenIdToBidIndex[_tokenId]];
        delete tokenIdToBid[_tokenId];

        emit BidCanceled(_tokenId);
        return true;
    }
 
    /** @dev Getting a sale offer info
        @param _tokenId NFT token id
        @return _seller Seller wallet address
        @return _price Offer price
        @return _sold Offer status    
     */
    function getOffer(uint256 _tokenId) public view returns (address _seller, uint256 _price, bool _sold) {
        Offer storage _offer = offers[tokenIdToOfferIndex[_tokenId]];
        return (_offer.seller, _offer.price, _offer.sold);
    }

    /** @dev Getting a sale offer info       
        @return _listOfOffers Active offer list           
     */
    function getAllActiveOffers() public view returns (Offer[] memory _listOfOffers) {

        /** TODO */
    }


    /** @dev Canceling a offer by offer owner
        @param _tokenId NFT token id       
        @return true if it's executed successfully

        @notice The offer must not has been sold
        @notice The offer owner can cancel own offer 

        @dev If seller was creator, the creator item will delete from creators array
    */
    function cancelOffer(uint256 _tokenId) public returns (bool) {
        require(offers[tokenIdToOfferIndex[_tokenId]].sold == false,"You can't cancel sold offer");
        require(offers[tokenIdToOfferIndex[_tokenId]].seller == msg.sender,"You don't have primesiion.");
        delete offers[tokenIdToOfferIndex[_tokenId]];
        delete tokenIdToOffer[_tokenId];

        /** TODO: if msg.sender was creator, the creator item delete from creators array */

        emit CancelOffer(_tokenId);
        return true;
    }

    /** @dev updating a offer price by offer owner
        @param _tokenId NFT token id       
        @param _price New price      
        @return true if it's executed successfully

        @notice The offer must not has been sold
        @notice The offer owner can update own offer 
        @notice The NFT token must be approved         
    */
    function updateOffer(uint256 _tokenId, uint256 _price) public returns (bool) {
        require(INFT_TOKEN(nftTokenContractAddress).getApproved(_tokenId) == address(this),"NFT must be approved");
        require(offers[tokenIdToOfferIndex[_tokenId]].sold == false,"NFT not available for update");
        require(offers[tokenIdToOfferIndex[_tokenId]].seller == msg.sender,"You don't have primesiion.");
        offers[tokenIdToOfferIndex[_tokenId]].price = _price;
        emit OfferUpdated(_tokenId, _price);
        return true;
    }

    /** @dev buying proccess
        @param _tokenId NFT token id  
        @return true if it's executed successfully

        @notice The offer must not has been sold
        @notice The buyer must have enough balance 

        @dev If the conditions are OK, 
             1) The price reduce from the buyer's account balance.
             2) The NFT token transfers to the buyer's wallet.
             3) The NFT royalty, if any, calculates and reduce from the sale price and transfer to creator account balance. 
             4) The platform fee, if any, calculates and reduced from the sale price and transfer to platform fee balance.  
             5) The rest of the sale price transfer to the seller account balance.      
    */
    function buyNFT(uint256 _tokenId) external payable returns (bool) { 
        require(offers[tokenIdToOfferIndex[_tokenId]].sold == false,"NFT not available for buy");        
        require(getNftOwner(_tokenId) != msg.sender, "You are NFT owner");
        require(INFT_TOKEN(nftTokenContractAddress).getApproved(_tokenId) == address(this),"NFT must be approved"); 
        uint256 price = offers[tokenIdToOfferIndex[_tokenId]].price;      
        require(balanceOf(msg.sender) >= price, "You don't have enough money in your account balance."); 
        _balances[msg.sender] -= price;  
        
        
        offers[tokenIdToOfferIndex[_tokenId]].sold = true;
        offers[tokenIdToOfferIndex[_tokenId]].price = 0;
        offers[tokenIdToOfferIndex[_tokenId]].sold_price = price;
        offers[tokenIdToOfferIndex[_tokenId]].seller;

        INFT_TOKEN(nftTokenContractAddress).safeTransferFrom(offers[tokenIdToOfferIndex[_tokenId]].seller,msg.sender,_tokenId);
        uint256 _sellerFee = price;
        address _nftCreator = getNftCreator(_tokenId);
        if (_nftCreator == creators[tokenIdToCreatorIndex[_tokenId]].creator) {
            uint256 royalty = creators[tokenIdToCreatorIndex[_tokenId]].royalty;
            if (royalty > 0) {
                uint256 royalteFee = royaltyFeeCalculator(royalty, price);
                if (royalteFee > 0 && royalteFee < price) {
                    _sellerFee -= royalteFee;
                    _balances[creators[tokenIdToCreatorIndex[_tokenId]].creator] += royalteFee;                   
                }
            }
        }
        if (platformFee > 0) {
            uint256 _platformFee = platformFeeCalculator(price);
            if (_platformFee > 0 && _platformFee < price) {
                _sellerFee -= _platformFee;
                platformBalance += _platformFee;               
            }
        }  
        _balances[offers[tokenIdToOfferIndex[_tokenId]].seller] += _sellerFee;
         emit BuyDone(_tokenId,price);
        return true;
    }

    
    /** @dev Sending funds from buyer or bidder to smart contract before buying or put a bid
        @return true if it's executed successfully    
     */
    function deposit() public payable returns (bool) {
        require(msg.value > 0 , "Value must be greater than zero.");
        _balances[msg.sender] += msg.value;
        emit DepositSucceed(msg.sender, msg.value);
        return true;
    }

    /** @dev Calculating royalty fee
        @param _royalty Royalty percent base on wei
        @param _price The NFT token price base on wei
        @return uint256 Royalty amount base on wei    
     */
    function royaltyFeeCalculator(uint256 _royalty, uint256 _price) public pure returns (uint256) {
        uint256 _royaltyPercent = _royalty / 100;
        uint256 _price_eth = _price / 1000000000000000000;
        return  _price_eth * _royaltyPercent;        
    }

    /** @dev Calculating platform fee       
        @param _price The NFT token price base on eth
        @return uint256 Platform fee amount base on wei    
     */
    function platformFeeCalculator(uint256 _price) public view returns (uint256) {
        uint256 _fee =  platformFee / 100;
        uint256 _price_eth = _price / 1000000000000000000;
        return _price_eth * _fee;        
    }
   
     /** @dev Withdrawing platform fee by smart contract owner
         @param _amount Withdrawing amount

         @notice Owner only withdraw platform fee, no more     
     */    
    function withdrawPlatformBlance(uint256 _amount) public payable onlyOwner {
        require(msg.value == _amount, "Value and  amount must be equal.");
        require(msg.value > 0, "Value must be greater than zero.");
        require(_amount <= platformBalance);
        platformBalance -= _amount;
        payable(msg.sender).transfer(_amount);
        emit WithdrawingSucceed(msg.sender, _amount);
    }

    /** @dev Withdrawing their users balance from smart contract by themselves
         @param _amount Withdrawing amount

         @notice Users can be the seller, the buyer, the creator or anyone who has the capital in this smart contract  
     */  
    function withdraw(uint256 _amount) public payable {
        require(msg.value == _amount, "Value and  amount must be equal.");
        require(msg.value > 0, "Value must be greater than zero.");
        require(_amount <= balanceOf(msg.sender));
        _balances[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);
        emit WithdrawingSucceed(msg.sender, _amount);
    }

    /** @dev Showing smart contract balance only
        @return uint256 Smart contract balance    
    */ 
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /** @dev Showing users balance only
        @param account User account address
        @return uint256 User balance 
     */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
    
}
