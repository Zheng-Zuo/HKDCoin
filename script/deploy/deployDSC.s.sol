// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DSC} from "src/DSC.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    function run() external returns (DSC, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.deployerKey);
        DSC dsc = new DSC();
        ERC1967Proxy proxy = new ERC1967Proxy(address(dsc), "");
        DSC(address(proxy)).initialize("HKD Coin", "HKDC");
        vm.stopBroadcast();

        return (DSC(address(proxy)), helperConfig);
    }
}
