// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MockDSCV2 is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    error ZeroAmount();
    error InsufficientBalance();

    // use reinitializer(n) modifier to re-initialize the contract
    // function initialize(string memory name, string memory symbol) public reinitializer(2) {
    //     __ERC20_init(name, symbol);
    //     __UUPSUpgradeable_init();
    //     __Ownable_init(msg.sender);
    // }

    function burn(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();

        _burn(msg.sender, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        _mint(to, amount);
    }

    function version() external pure returns (uint256) {
        return 2;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
