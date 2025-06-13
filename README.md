## HKDC Protocol

**A modular, upgradeable, and DAO-governed protocol for a decentralized HKD-pegged stablecoin system, built with Foundry and Hardhat. The protocol supports multi-collateral minting, liquidation, and decentralized governance.**

## Overview

This project implements a decentralized stablecoin system with the following core components:

-   HKDCEngine: The main protocol contract for collateral management, minting, burning, and liquidation of the HKDC stablecoin.
-   DSC: An upgradeable ERC20 stablecoin contract (HKDC), with role-based minting and burning.
-   HKDCG: The governance token (HKDCG), used for voting in the DAO.
-   HKDCDAO: A Governor contract for decentralized protocol upgrades and parameter changes, using the governance token.
-   TimeLock: A timelock controller for secure, delayed execution of DAO proposals.

## Features

-   Multi-collateral: Supports multiple collateral types (e.g., ETH, WETH, WBTC).
-   Oracle Integration: Uses price feeds for collateral valuation and liquidation logic.
-   Liquidation: Automated liquidation of under-collateralized positions.
-   DAO Governance: Protocol upgrades and parameter changes are managed by token holders via on-chain voting.
-   Upgradeable Stablecoin: The HKDC token is upgradeable and governed by the DAO.
