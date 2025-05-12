// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DeployDSC, DSC, HelperConfig} from "script/deploy/deployDSC.s.sol";
import {MockDSCV2} from "src/mock/MockDSCV2.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DSCUpgradeTest is Test {
    DSC public dscProxy;
    HelperConfig public helperConfig;
    MockDSCV2 public newImplementation;
    address deployer;
    address user;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 22435999);
        (dscProxy, helperConfig) = new DeployDSC().run();
        deployer = vm.addr(helperConfig.getConfig().deployerKey);
        user = makeAddr("user");
        newImplementation = new MockDSCV2();

        vm.startPrank(deployer);
        dscProxy.grantRole(dscProxy.UPGRADE_ROLE(), deployer);
        vm.stopPrank();
    }

    modifier onlyDeployer() {
        vm.startPrank(deployer);
        _;
        vm.stopPrank();
    }

    modifier onlyUser() {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function test_dscInitialized() public view {
        assertEq(dscProxy.hasRole(dscProxy.DEFAULT_ADMIN_ROLE(), deployer), true);
        assertEq(dscProxy.hasRole(dscProxy.ADMIN_ROLE(), deployer), false);
        assertEq(dscProxy.hasRole(dscProxy.UPGRADE_ROLE(), deployer), true);
        assertEq(dscProxy.hasRole(dscProxy.UPGRADE_ROLE(), user), false);
        assertEq(dscProxy.version(), 1);
    }

    function test_unauthorizedUpgradeNotAllowed() public onlyUser {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, dscProxy.UPGRADE_ROLE()
            )
        );
        dscProxy.upgradeToAndCall(address(newImplementation), "");
    }

    function test_authorizedUpgradeAllowed() public onlyDeployer {
        dscProxy.upgradeToAndCall(address(newImplementation), "");
        assertEq(dscProxy.version(), 2);
    }
}
