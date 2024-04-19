// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = _NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC725Y is IERC165 {
    event DataChanged(bytes32 indexed dataKey, bytes dataValue);

    function getData(
        bytes32 dataKey
    ) external view returns (bytes memory dataValue);

    function getDataBatch(
        bytes32[] memory dataKeys
    ) external view returns (bytes[] memory dataValues);

    function setData(bytes32 dataKey, bytes memory dataValue) external payable;

    function setDataBatch(
        bytes32[] memory dataKeys,
        bytes[] memory dataValues
    ) external payable;
}

interface ILSP8IdentifiableDigitalAsset is IERC165, IERC725Y {
    event Transfer(
        address operator,
        address indexed from,
        address indexed to,
        bytes32 indexed tokenId,
        bool force,
        bytes data
    );

    event AuthorizedOperator(
        address indexed operator,
        address indexed tokenOwner,
        bytes32 indexed tokenId
    );

    event RevokedOperator(
        address indexed operator,
        address indexed tokenOwner,
        bytes32 indexed tokenId
    );

    function totalSupply() external view returns (uint256);

    function balanceOf(address tokenOwner) external view returns (uint256);

    function tokenOwnerOf(bytes32 tokenId) external view returns (address);

    function tokenIdsOf(address tokenOwner) external view returns (bytes32[] memory);

    function authorizeOperator(address operator, bytes32 tokenId) external;

    function revokeOperator(address operator, bytes32 tokenId) external;

    function isOperatorFor(address operator, bytes32 tokenId) external view returns (bool);

    function getOperatorsOf(bytes32 tokenId) external view returns (address[] memory);

    function transfer(
        address from,
        address to,
        bytes32 tokenId,
        bool force,
        bytes memory data
    ) external;

    function transferBatch(
        address[] memory from,
        address[] memory to,
        bytes32[] memory tokenId,
        bool force,
        bytes[] memory data
    ) external;
}

contract LSPLendingContract is ReentrancyGuard, Ownable {
    struct LoanDetails {
        address nftAddress;
        address lender;
        address borrower;
        uint256 loanId;
        uint256 duration;
        uint256 amount;
        uint256 interest;
        uint256 royalty;
        uint256 durationCounter;
        bytes32 tokenId;
        bool accepted;
        bool paid;
    }

    uint256 public loanIdCounter;

    mapping(uint256 => LoanDetails) public loans;
    mapping(uint256 => bool) public loanExistence;

    event LoanProposed(
        address indexed nftAddress,
        uint256 indexed loanId,
        uint256 duration,
        uint256 interest
    );

    event LoanModified(
        uint256 indexed loanId,
        uint256 indexed duration,
        uint256 indexed amount,
        uint256 interest,
        uint256 royalty
    );

    event LoanRemoved(
        uint256 indexed loanId
    );

    event LoanOffered(
        address indexed nftAddress,
        address indexed lender,
        uint256 indexed loanId,
        uint256 amount
    );

    event LoanAccepted(
        address indexed nftAddress,
        address indexed borrower,
        uint256 indexed loanId,
        bytes32 tokenId
    );

    event LoanRepaid(
        uint256 indexed loanId,
        uint256 indexed amountPaid
    );

    event LoanLiquidated(
        uint256 indexed loanId,
        address indexed nftAddress,
        bytes32 indexed tokenId
    );

    modifier checkLoanExistence(uint256 loanId) {
        require(
            loanExistence[loanId],
            "Loan doesn't exist"
        );
        _;
    }

    function proposeLoan(
        address nftAddress,
        uint256 duration,
        uint256 interest,
        uint256 royalty
    ) public nonReentrant onlyOwner {
        require(
            duration > 0 && duration < 365 days,
            "Invalid liquidation duration"
        );

        _setLoan(
            nftAddress,
            address(0),
            address(0),
            loanIdCounter,
            duration,
            0,
            interest,
            royalty,
            0,
            0,
            false,
            false
        );

        loanExistence[loanIdCounter] = true;
        loanIdCounter++;

        emit LoanProposed(nftAddress, duration, interest, loanIdCounter);
    }

    function modifyLoan(
        uint256 loanId,
        uint256 duration,
        uint256 amount,
        uint256 interest,
        uint256 royalty
    ) public nonReentrant checkLoanExistence(loanId) onlyOwner {
        LoanDetails memory loanDetails = loans[loanId];

        require(
            !loanDetails.accepted,
            "Loan is already accepted"
        );

        loanDetails.duration = duration;
        loanDetails.amount = amount;
        loanDetails.interest = interest;
        loanDetails.royalty = royalty;

        loans[loanId] = loanDetails;

        emit LoanModified(loanId, duration, amount, interest, royalty);
    }

    function removeLoan(
        uint256 loanId
    ) public nonReentrant checkLoanExistence(loanId) onlyOwner {
        delete loans[loanId];
        loanIdCounter--;
        
        emit LoanRemoved(loanId);
    }

    function offerLoan(
        uint256 loanId
    ) public payable nonReentrant checkLoanExistence(loanId) {
        LoanDetails memory loanDetails = loans[loanId];

        require(
            msg.value > 0,
            "Amount is insufficient"
        );

        loanDetails.lender = msg.sender;
        loanDetails.amount = msg.value;

        loans[loanId] = loanDetails;

        emit LoanOffered(loanDetails.nftAddress, msg.sender, loanId, msg.value);
    }

    function acceptLoan(uint256 loanId, bytes32 tokenId) public nonReentrant checkLoanExistence(loanId) {
        LoanDetails memory loanDetails = loans[loanId];

        require(
            !loanDetails.accepted,
            "Loan is already accepted"
        );

        require(
            loanDetails.amount >= 0,
            "Amount is insufficient"
        );

        require(
            ILSP8IdentifiableDigitalAsset(loanDetails.nftAddress).tokenOwnerOf(tokenId) == msg.sender,
            "Sender doesn't own this LSP8"
        );

        _transferLSP8(loanDetails.nftAddress, msg.sender, address(this), tokenId, false, 1);

        loanDetails.borrower = msg.sender;
        loanDetails.durationCounter = loanDetails.duration + block.timestamp;
        loanDetails.tokenId = tokenId;
        loanDetails.accepted = true;

        loans[loanId] = loanDetails;

        emit LoanAccepted(loanDetails.nftAddress, loanDetails.borrower, loanId, tokenId);
    }

    function repayLoan(uint256 loanId) public payable nonReentrant checkLoanExistence(loanId) {
        LoanDetails memory loanDetails = loans[loanId];

        require(
            loanDetails.accepted,
            "Loan should be accepted"
        );

        require(
            !loanDetails.paid,
            "Loan is already paid"
        );

        uint256 amount = loanDetails.amount;
        uint256 interest = (loanDetails.interest * amount) / 100;

        uint256 totalAmount = amount + interest;

        require(
            msg.value >= totalAmount,
            "Repay amount is insufficient"
        );

        (bool success1,) = owner().call{value: (totalAmount * loanDetails.royalty) / 100}("");
        (bool success2,) = loanDetails.lender.call{value: totalAmount - (totalAmount * loanDetails.royalty) / 100}("");

        require(
            success1 && success2,
            "Asset's failed to be sent"
        );

        _transferLSP8(loanDetails.nftAddress, address(this), loanDetails.borrower, loanDetails.tokenId, false, 1);

        loanDetails.paid = true;
        loans[loanId] = loanDetails;

        emit LoanRepaid(loanId, totalAmount);
    }

    function liquidateLoan(uint256 loanId) public nonReentrant checkLoanExistence(loanId) {
        LoanDetails memory loanDetails = loans[loanId];

        require(
            !loanDetails.paid,
            "Loan is already paid"
        );

        require(
            block.timestamp >= loanDetails.durationCounter,
            "Loan is not due yet"
        );

        _transferLSP8(loanDetails.nftAddress, address(this), loanDetails.lender, loanDetails.tokenId, false, 1);

        loanDetails.paid = true;
        loans[loanId] = loanDetails;

        emit LoanLiquidated(loanId, loanDetails.nftAddress, loanDetails.tokenId);
    }

    function _setLoan(
        address _nftAddress,
        address _lender,
        address _borrower,
        uint256 _loanId,        
        uint256 _duration,
        uint256 _amount,
        uint256 _interest,
        uint256 _royalty,
        uint256 _durationCounter,
        bytes32 _tokenId,
        bool _accepted,
        bool _paid
    ) internal {
        loans[_loanId] = LoanDetails({            
            nftAddress: _nftAddress,
            lender: _lender,
            borrower: _borrower,
            loanId: _loanId,
            duration: _duration,
            amount: _amount,
            interest: _interest,
            royalty: _royalty,
            durationCounter: _durationCounter,
            tokenId: _tokenId,
            accepted: _accepted,            
            paid: _paid
        });
    }

    function _transferLSP8(
        address LSP8Address,
        address from,
        address to,
        bytes32 tokenId,
        bool force,
        uint256 amount
    ) internal {
        ILSP8IdentifiableDigitalAsset(LSP8Address).transfer(
            from,
            to,
            tokenId,
            force,
            _returnLSPTransferData(from, to, amount)
        );
    }

    function _returnLSPTransferData(
        address from,
        address to,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return
        abi.encodeWithSignature(
            "universalReceiver(bytes32 typeId, bytes memory data)",
            keccak256("TOKEN_RECEIVE"),
            abi.encodePacked(from, to, amount)
        );
    }
}