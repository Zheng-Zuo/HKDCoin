// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DeployDSC, DSC, HelperConfig} from "script/deploy/deployDSC.s.sol";
import {MockDSCV2} from "src/mock/MockDSCV2.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DSCUpgradeTest is Test {
    DSC public dscProxy;
    HelperConfig public helperConfig;
    MockDSCV2 public newImplementation;

    address user;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 22435999);
        (dscProxy, helperConfig) = new DeployDSC().run();
        user = makeAddr("user");
        newImplementation = new MockDSCV2();
    }

    modifier onlyOwner() {
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vm.startPrank(vm.addr(config.deployerKey));
        _;
        vm.stopPrank();
    }

    modifier onlyUser() {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function test_dscInitialized() public view {
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        address owner = dscProxy.owner();
        assertEq(owner, vm.addr(config.deployerKey));
        assertEq(dscProxy.version(), 1);
    }

    function test_unauthorizedUpgradeNotAllowed() public onlyUser {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        dscProxy.upgradeToAndCall(address(newImplementation), "");
    }

    function test_authorizedUpgradeAllowed() public onlyOwner {
        dscProxy.upgradeToAndCall(address(newImplementation), "");
        assertEq(dscProxy.version(), 2);
    }
}
