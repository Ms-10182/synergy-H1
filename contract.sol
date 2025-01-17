// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Roles.sol";

contract ExpirableToken is ERC20,ReentrancyGuard {

    // Struct to store token batches with amount and expiration time
    struct TokenBatch {
        uint256 amount;
        uint256 expiration;
    }

    // Mapping to store token batches for each address
    mapping(address => TokenBatch[]) private _tokenBatches;
    using Roles for Roles.Role;

    Roles.Role private _owners;
    Roles.Role private _minters;


    // Events to log various actions
    event TokensMinted(address indexed to, uint256 amount, uint256 expiration);
    event TokensBurned(address indexed account, uint256 amount);
    event TokensTransferred(address indexed from, address indexed to, uint256 amount, uint256 expiration);
    event MinterAdded(address indexed by, address[] indexed minterAddress);
    event OwnerAdded(address indexed by, address[] indexed OwnerAddress);
    event BalanceUpdated(address indexed user, uint newAmount);
    event TokensExpired(address indexed user, uint amount);

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }
    // Constructor to initialize the contract with name, symbol, minters, and owners
    constructor() ERC20("Synergy coin", "SGC") {
        _owners.add(msg.sender);
    }

    /*
    @dev Adds new owners to the contract.
    @param newOwners The addresses of the new owners.
    */
    function addOwners(address[] memory newOwners) external {
        require(newOwners.length > 0, "empty owner list");
        require(_owners.has(msg.sender), "DOES_NOT_HAVE_OWNER_ROLE");
        for (uint i = 0; i < newOwners.length; i++) {
            _owners.add(newOwners[i]);
        }
        emit OwnerAdded(msg.sender, newOwners);
    }

    /*
    @dev Adds new minters to the contract.
    @param newMinters The addresses of the new minters.
    */
    function addMinters(address[] memory newMinters) external {
        require(newMinters.length > 0, "empty minter list");
        require(_owners.has(msg.sender), "DOES_NOT_HAVE_OWNER_ROLE");
        for (uint i = 0; i < newMinters.length; i++) {
            _minters.add(newMinters[i]);
        }
        emit MinterAdded(msg.sender, newMinters);
    }

    /*
    @dev Removes existing minters from the contract.
    @param minters The addresses of the minters to be removed.
    */
    function removeMinters(address[] memory minters) external {
        require(minters.length > 0, "empty minter list");
        require(_owners.has(msg.sender), "DOES_NOT_HAVE_OWNER_ROLE");
        for (uint i = 0; i < minters.length; i++) {
            _minters.remove(minters[i]);
        }
    }
    function removeOwners(address[] memory owners) external {
        require(owners.length > 0, "empty minter list");
        require(_owners.has(msg.sender), "DOES_NOT_HAVE_OWNER_ROLE");
        for (uint i = 0; i < owners.length; i++) {
            _minters.remove(owners[i]);
        }
    }

    /*
    @dev Mints new tokens to a specified address with an expiration time.
    @param to The address to receive the tokens.
    @param amount The amount of tokens to mint.
    @param expiration The expiration time in seconds from the current block timestamp.
    */
    function mint(address to, uint256 amount, uint256 expiration) public {
        require(_minters.has(msg.sender) || _owners.has(msg.sender), "DOES_NOT_HAVE_MINTER_ROLE");
        require(amount > 0, "amount 0 or low");
        require(to != address(0), "address is 0 can't mint");
        _mint(to, amount);
        _tokenBatches[to].push(TokenBatch(amount, block.timestamp + expiration));
        emit TokensMinted(to, amount, block.timestamp + expiration);
    }

    /*
    @dev Returns the balance of non-expired tokens for a specified address.
    @param account The address to query the balance of.
    @return The balance of non-expired tokens.
    */
    function balanceOf(address account) public view override returns (uint256) {
        uint256 balance = 0;
        for (uint256 i = 0; i < _tokenBatches[account].length; i++) {
            if (block.timestamp < _tokenBatches[account][i].expiration) {
                balance += _tokenBatches[account][i].amount;
            }
        }
        return balance;
    }

    /*
    @dev Transfers tokens to a specified address with a reentrancy guard.
    @param recipient The address to receive the tokens.
    @param amount The amount of tokens to transfer.
    @return A boolean value indicating whether the operation succeeded.
    */
    function transfer(address recipient, uint256 amount) public override nonReentrant returns (bool) {
        require(recipient != address(0), "address can not be 0");
        require(amount > 0, "amount too low");
        require(balanceOf(msg.sender) > amount, "balance is low");
        _updateExpiredTokens(msg.sender);
        // require(_availableBalance(msg.sender) >= amount, "Insufficient balance");
        (uint256 idx, bool isAvail) = getEarliestEpoch(msg.sender, amount);
        require(isAvail, "no epoch has valid amount");
        _reduceBalance(msg.sender, amount, idx);
        _transfer(msg.sender, recipient, amount);
        _tokenBatches[recipient].push(TokenBatch(amount, _tokenBatches[msg.sender][idx].expiration));
        emit TokensTransferred(msg.sender, recipient, amount, _tokenBatches[msg.sender][idx].expiration);
        return true;
    }

    /*
    @dev Transfers tokens from one address to another with a reentrancy guard.
    @param sender The address to send the tokens from.
    @param recipient The address to receive the tokens.
    @param amount The amount of tokens to transfer.
    @return A boolean value indicating whether the operation succeeded.
    */
    function transferFrom(address sender, address recipient, uint256 amount) public override nonReentrant returns (bool) {
        require(recipient != address(0), "address cannot be 0");
        require(amount > 0, "amount too low");
        require(balanceOf(sender) > amount, "balance is low");
        _updateExpiredTokens(sender);
        _updateExpiredTokens(msg.sender);
        // require(_availableBalance(sender) >= amount, "Insufficient balance");
        (uint256 idx, bool isAvail) = getEarliestEpoch(sender, amount);
        require(isAvail, "No epoch has valid amount");
        _reduceBalance(sender, amount, idx);
        _transfer(sender, recipient, amount);
        _tokenBatches[recipient].push(TokenBatch(amount, _tokenBatches[sender][idx].expiration));
        emit TokensTransferred(sender, recipient, amount, _tokenBatches[sender][idx].expiration);
        return true;
    }

    /*
    @dev Internal function to update expired tokens for a specified address.
    @param account The address to update expired tokens for.
    */
    function _updateExpiredTokens(address account) internal {
        uint256 expiredAmount = 0;
        for (uint256 i = 0; i < _tokenBatches[account].length; ) {
            if (block.timestamp >= _tokenBatches[account][i].expiration) {
                expiredAmount += _tokenBatches[account][i].amount;
                // Remove expired batch
                _tokenBatches[account][i] = _tokenBatches[account][_tokenBatches[account].length - 1];
                _tokenBatches[account].pop();
            } else {
                i++;
            }
        }
        if (expiredAmount > 0) {
            _burn(account, expiredAmount);
            emit TokensExpired(account, expiredAmount);
        }
        emit BalanceUpdated(account, balanceOf(account));
    }

    function flushExpired(address account) external {
        _updateExpiredTokens(account);
        emit BalanceUpdated(account, balanceOf(account));

    }

    /*
    @dev Internal function to get the available balance of non-expired tokens for a specified address.
    @param account The address to query the available balance of.
    @return The available balance of non-expired tokens.
    */
    function _availableBalance(address account) internal view returns (uint256) {
        return balanceOf(account);
    }

    /*
    @dev Internal function to reduce the balance of a specific token batch.
    @param account The address to reduce the balance of.
    @param amount The amount to reduce the balance by.
    @param idx The index of the token batch to reduce the balance from.
    */
    function _reduceBalance(address account, uint256 amount, uint idx) internal {
        require(balanceOf(account) >= amount, "Insufficient balance");
        require(_tokenBatches[account][idx].amount >= amount, "Insufficient epoch balance");
        _tokenBatches[account][idx].amount -= amount;
    }

    /*
    @dev Returns the token batches for a specified address.
    @param account The address to query the token batches of.
    @return The token batches for the specified address.
    */
    function isExpired(address account) public view returns (TokenBatch[] memory) {
        return _tokenBatches[account];
    }

    /*
    @dev Internal function to get the earliest epoch with sufficient balance for a specified address.
    @param account The address to query the earliest epoch of.
    @param amount The amount to query the earliest epoch for.
    @return The index of the earliest epoch and a boolean indicating whether the epoch is available.
    */
    function getEarliestEpoch(address account, uint256 amount) internal view returns (uint256, bool) {
        for (uint256 i = 0; i < _tokenBatches[account].length; i++) {
            if (block.timestamp < _tokenBatches[account][i].expiration && _tokenBatches[account][i].amount >= amount) {
                return (i, true);
            }
        }
        return (0, false);
    }
}
