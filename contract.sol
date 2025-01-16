// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ExpirableToken is ERC20,ReentrancyGuard {
    struct TokenBatch {
        uint256 amount;
        uint256 expiration;
    }

    mapping(address => TokenBatch[]) private _tokenBatches;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    event TokensMinted(address indexed to, uint256 amount, uint256 expiration);
    event TokensBurned(address indexed account, uint256 amount);
    event TokensTransferred(address indexed from, address indexed to, uint256 amount, uint256 expiration);

    function mint(address to,uint256 amount,uint256 expiration) public {
        require(amount>0,"amount 0 or low");
        require(to!=address(0),"address is 0 can't mint");
        _mint(to, amount);
        _tokenBatches[to].push(TokenBatch(amount, block.timestamp + expiration));
        emit TokensMinted(to, amount, block.timestamp + expiration);
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 balance = 0;
        for (uint256 i = 0; i < _tokenBatches[account].length; i++) {
            if (block.timestamp < _tokenBatches[account][i].expiration) {
                balance += _tokenBatches[account][i].amount;
            }
        }
        return balance;
    }

    function transfer(address recipient, uint256 amount)public override nonReentrant returns (bool){
        require(recipient!=address(0),"address can not be 0");
        require(amount>0,"amount too low");
        require(balanceOf(msg.sender)>amount,"balance is low");
        _updateExpiredTokens(msg.sender);
        require(_availableBalance(msg.sender) >= amount,"Insufficient balance");
        (uint256 idx, bool isAvail) = getEarliestEpoch(msg.sender, amount);
        require(isAvail, "no epoch has valid amount");
        _reduceBalance(msg.sender, amount,idx);
        _transfer(msg.sender, recipient, amount);

        _tokenBatches[recipient].push(TokenBatch(amount, _tokenBatches[msg.sender][idx].expiration));
        emit TokensTransferred(msg.sender, recipient, amount, _tokenBatches[msg.sender][idx].expiration);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override nonReentrant  returns (bool) {
        require(recipient!=address(0),"address cannot be 0");
        require(amount>0,"amount too low");
        require(balanceOf(sender)>amount,"balance is low");


        _updateExpiredTokens(sender);
        _updateExpiredTokens(msg.sender);

        require(_availableBalance(sender) >= amount, "Insufficient balance");
        (uint256 idx, bool isAvail) = getEarliestEpoch(sender, amount);
        require(isAvail, "No epoch has valid amount");
        _reduceBalance(sender, amount,idx);
        _transfer(sender, recipient, amount);
        _tokenBatches[recipient].push(TokenBatch(amount, _tokenBatches[sender][idx].expiration));
        emit TokensTransferred(sender, recipient, amount, _tokenBatches[sender][idx].expiration);
        return true;
    }

    function _updateExpiredTokens(address account) internal   {
        for (uint256 i = 0; i < _tokenBatches[account].length; ) {
            if (block.timestamp >= _tokenBatches[account][i].expiration) {
                if (_tokenBatches[account][i].amount > 0) {
                    _burn(account, _tokenBatches[account][i].amount);
                }
                // Remove expired batch
                _tokenBatches[account][i] = _tokenBatches[account][_tokenBatches[account].length - 1];
                _tokenBatches[account].pop();
            } else {
                i++;
            }
        }
    }


    function _availableBalance(address account)internal view returns (uint256){
        uint256 balance = 0;
        for (uint256 i = 0; i < _tokenBatches[account].length; i++) {
            if (block.timestamp < _tokenBatches[account][i].expiration) {
                if (_tokenBatches[account][i].amount == 0) {
                    continue;
                }
                balance += _tokenBatches[account][i].amount;
            }
        }
        return balance;
    }

    function _reduceBalance(address account, uint256 amount, uint idx) internal {
        require(balanceOf(account)>=amount, "Insufficient balance");
        require(_tokenBatches[account][idx].amount >= amount, "Insufficient epoch balance");
        _tokenBatches[account][idx].amount-=amount;
    }

    function isExpired(address account)public view returns (TokenBatch[] memory)
    {
        return _tokenBatches[account];
    }

    function getEarliestEpoch(address account, uint256 amount)
        internal
        view
        returns (uint256, bool)
    {
        for (uint256 i = 0; i < _tokenBatches[account].length; i++) {
            if (
                block.timestamp < _tokenBatches[account][i].expiration &&
                _tokenBatches[account][i].amount >= amount
            ) {
                return (i, true);
            }
        }
        return (0, false);
    }
}
