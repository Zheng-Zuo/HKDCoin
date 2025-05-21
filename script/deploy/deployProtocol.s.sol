// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {TimeLock, HKDCDAO, HKDCG, HelperConfig, DeployDAO} from "script/deploy/deployDAO.s.sol";
import {DeployDSC, DSC} from "script/deploy/deployDSC.s.sol";
import {HKDCEngine} from "src/HKDCEngine.sol";

contract DeployProtocol is Script {
    HKDCG public hkdcg;
    TimeLock public timelock;
    HKDCDAO public hkdcdao;
    HelperConfig public helperConfig;
    DSC public dscProxy;
    HKDCEngine public hkdce;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (HKDCEngine, DSC, HKDCG, TimeLock, HKDCDAO, HelperConfig) {
        (hkdcg, timelock, hkdcdao, helperConfig) = new DeployDAO().run();
        (dscProxy,) = new DeployDSC().run();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        tokenAddresses = [address(0), config.weth, config.wbtc];
        priceFeedAddresses = [config.wethUsdPriceFeed, config.wethUsdPriceFeed, config.wbtcUsdPriceFeed];

        vm.startBroadcast(config.deployerKey);
        hkdce = new HKDCEngine(tokenAddresses, priceFeedAddresses, address(dscProxy), config.protocolFeeRecipient);
        dscProxy.grantRole(dscProxy.UPGRADE_ROLE(), address(timelock));
        dscProxy.grantRole(dscProxy.MINTER_ROLE(), address(hkdce));
        dscProxy.grantRole(dscProxy.BURNER_ROLE(), address(hkdce));
        vm.stopBroadcast();

        return (hkdce, dscProxy, hkdcg, timelock, hkdcdao, helperConfig);
    }
}
