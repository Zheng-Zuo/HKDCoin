// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DSC is ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    error ZeroAmount();
    error InsufficientBalance();

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        _;
    }

    function initialize(string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function burn(uint256 amount) external onlyRole(BURNER_ROLE) moreThanZero(amount) {
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();
        _burn(msg.sender, amount);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) moreThanZero(amount) {
        _mint(to, amount);
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADE_ROLE) {}
}
