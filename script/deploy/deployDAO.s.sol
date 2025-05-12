// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {TimeLock} from "src/TimeLock.sol";
import {HKDCDAO} from "src/HKDCDAO.sol";
import {HKDCG} from "src/HKDCG.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDAO is Script {
    uint256 public constant MIN_DELAY = 3600 * 24 * 3; // 3 days
    address public deployer;
    address[] proposers;
    address[] executors;

    function run() external returns (HKDCG, TimeLock, HKDCDAO, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        deployer = vm.addr(config.deployerKey);

        vm.startBroadcast(config.deployerKey);
        HKDCG hkdcg = new HKDCG(deployer);
        TimeLock timelock = new TimeLock(MIN_DELAY, proposers, executors);
        HKDCDAO hkdcdao = new HKDCDAO(hkdcg, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(hkdcdao));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, deployer);

        vm.stopBroadcast();

        return (hkdcg, timelock, hkdcdao, helperConfig);
    }
}
