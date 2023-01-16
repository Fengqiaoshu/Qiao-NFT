// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
contract QiaoNFT is Ownable,ReentrancyGuard,ERC721Enumerable{
    using Strings for uint256;
    // 定义变量
    uint256 public MAX_NFT = 1000;                                          //合约最大发行数量，表示最多能够发行的 NFT 数量
    uint256 public MAX_MINT_PRESALE = 5;                                    //预售最大发行数量，表示预售期间最多能够发行的 NFT 数量。
	uint256 public MAX_MINT_SALE = 5;                                       //售卖最大发行数量，表示售卖期间最多能够发行的 NFT 数量
    uint256 public MAX_MINT_WL = 3;                                         //白名单最大发行数量，表示白名单中每个用户最多能够购买的 NFT 数量。

    uint256 public MAX_BY_MINT_IN_TRANSACTION_PRESALE = 5;                  //在预售的时候最大的mint数量
	uint256 public MAX_BY_MINT_IN_TRANSACTION_SALE = 5;                     //在公售的时候最大的mint数量

    uint256 public PRESALE_MINTED;                                          //预售已发行的 NFT 数量
	uint256 public SALE_MINTED;                                             //公售已发行的 NFT 数量。
	uint256 public GIVEAWAY_MINTED;                                         //赠送已发行的 NFT 数量。

    uint256 public PRESALE_PRICE = 0.06 * 1000000000000000000;              //预售 NFT 的价格，以 wei 为单位。
	uint256 public SALE_PRICE =  0.08 * 1000000000000000000;                //售卖 NFT 的价格，以 wei 为单位。

    bool public presaleEnable = false;                                      //预售开关，如果为 true，则合约处于预售状态，可以进行预售操作，如果为 false，则合约不能进行预售操作。
	bool public saleEnable = false;                                         //售卖开关，如果为 true，则合约处于售卖状态，可以进行售卖操作，如果为 false，则合约不能进行售卖操作。                     
    string private baseURI;                                                 // 图片 NFT 在 IPFS 上的基础 URI
	bytes32 public merkleRoot;                                              //Merkle 树的根节点。
    uint private unlockDate;                                                //销售开始时间。
    uint256 public constant WL_PRICE_PER_TOKEN = 0.06 * 1000000000000000000;       //白名单中 NFT 的购买价格，以 wei 为单位。   
    event minted(address to, uint256 tokenId, string token_IPFS_URI);              //发行 NFT 的事件         
    mapping(address => uint256) private _allowList;                         //白名单映射，存储白名单中每个用户可以购买的 NFT 数量。
	struct User {
		uint256 presalemint;    //预售mint                                  //User结构体 用来记录
		uint256 salemint;       //公售mint
    }
	mapping (address => User) public users;                                 //User结构体放入到映射users中

    // 构造函数在合约部署自动调用erc721并且传参 代币名字和 符号
    constructor() ERC721("Qiaonft", "Qiao") {  
    }

    //开始函数部分
    // 设置白名单 只能外部调用 
    function setAllowList(address[] calldata addresses)external onlyOwner{
      // 通过for循环循环数字长度
      for (uint256 i = 0;i < addresses.length; i++){
          //循环写入白单最大mint数量
          _allowList[addresses[i]] = MAX_MINT_WL;
      }
    }

    // 白名单购买nft
    function mintAllowList(uint8 numberOfTokens) external payable{
        //先确定nft总量
        uint256 ts = totalSupply();
        //验证是否是发售时间
        require(block.timestamp >=unlockDate,"The sale is not start yet");
        //验证mint个数是否符合_allowList下的数量
        require(numberOfTokens <= _allowList[msg.sender], "Exceeded max available to purchase");
        //验证加上mint的数量是否超过最大的数量
        require( ts + numberOfTokens <= MAX_NFT,"Purchase would exceed max tokens");
        //验证支付的eth是否足够
        require(WL_PRICE_PER_TOKEN * numberOfTokens <= msg.value,"Ether value sent is not correct" );
        _allowList[msg.sender] -= numberOfTokens;
        for (uint256 i = 0; i < numberOfTokens; i++) {
            _safeMint(msg.sender, ts + i);
        }
    }

    // 白单预售 需要提供 Merkle 树证明，并且只能在预售期间调用。
    function mintPresaleNFT(uint256 _count, bytes32[] calldata merkleProof)public payable nonReentrant {

        bytes32 node = keccak256(abi.encodePacked(msg.sender));
		uint256 totalSupply = totalSupply();
		require(presaleEnable, "Pre-sale is not enable");
        require(totalSupply + _count <= MAX_NFT, "Exceeds max limit");
		require(MerkleProof.verify(merkleProof, merkleRoot, node), "MerkleDistributor: Invalid proof.");
		require(users[msg.sender].presalemint + _count <= MAX_MINT_PRESALE,"Exceeds max mint limit per wallet");
		require(_count <= MAX_BY_MINT_IN_TRANSACTION_PRESALE,"Exceeds max mint limit per tnx");
		require(msg.value >= PRESALE_PRICE * _count,"Value below price");
		for (uint256 i = 0; i < _count; i++) {
            _safeMint(msg.sender, totalSupply + i);
			PRESALE_MINTED++;
        }
		users[msg.sender].presalemint = users[msg.sender].presalemint + _count;
    }
    

    //空投NFT，只有合约拥有者可以调用。
	function mintGiveawayNFT(address _to, uint256 _count) public onlyOwner{
        //先确定nft总量
	    uint256 totalSupply = totalSupply();
        //判断空投是否会超出最大的nft数量
        require(
            totalSupply + _count <= MAX_NFT, 
            "Max limit"
        );
        //循环把nft依次转入对方的地址
		for (uint256 i = 0; i < _count; i++) {
            _safeMint(_to, totalSupply + i);
			GIVEAWAY_MINTED++; 
        }
    }
    
    // 公开发售
    //查询 图片 NFT 在 IPFS 上的基础 URI
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
    //修改 图片 NFT 在 IPFS 上的基础 URI
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;

        
    }


}