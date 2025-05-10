// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

contract HKDCG is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes {
    error ZeroAmount();
    error ExceedMaxSupply();

    uint256 public constant MAX_SUPPLY = 1e9 * 1e18;

    constructor(address treasury) ERC20("HKD Coin Governor Token", "HKDCG") ERC20Permit("HKDCG") {
        _mint(treasury, MAX_SUPPLY);
    }

    // The following functions are overrides required by Solidity.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
