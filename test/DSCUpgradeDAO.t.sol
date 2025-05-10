// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DeployDAO, HKDCG, TimeLock, HKDCEngine, HelperConfig} from "script/deploy/deployDao.s.sol";
import {DeployDSC, DSC} from "script/deploy/deployDSC.s.sol";
import {MockDSCV2} from "src/mock/MockDSCV2.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DSCUpgradeDAO is Test {
    HKDCG public hkdcg;
    TimeLock public timelock;
    HKDCEngine public hkdce;
    HelperConfig public helperConfig;
    DSC public dscProxy;
    MockDSCV2 public newImplementation;
    address public deployer;

    bytes[] public functionCalls;
    address[] public addressesToCall;
    uint256[] public values;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 22435999);
        (hkdcg, timelock, hkdce, helperConfig) = new DeployDAO().run();
        (dscProxy,) = new DeployDSC().run();
        newImplementation = new MockDSCV2();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        deployer = vm.addr(config.deployerKey);

        vm.startPrank(deployer);
        dscProxy.transferOwnership(address(timelock));
        vm.stopPrank();
    }

    modifier onlyDeployer() {
        vm.startPrank(deployer);
        _;
        vm.stopPrank();
    }

    function test_initialState() public view {
        assertEq(dscProxy.owner(), address(timelock));
        assertEq(dscProxy.version(), 1);
        assertEq(hkdcg.getVotes(deployer), 0);
        assertEq(hkdcg.totalSupply(), hkdcg.balanceOf(deployer));
    }

    function test_unauthorizedUpgradeNotAllowed() public onlyDeployer {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, deployer));
        dscProxy.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgradeWithDAO() public onlyDeployer {
        hkdcg.delegate(deployer);
        uint256 votingDelay = hkdce.votingDelay();
        uint256 votingPeriod = hkdce.votingPeriod();
        uint256 minDelay = timelock.getMinDelay();

        // 1. propose to the DAO
        string memory description = "upgrade HKDC";
        bytes memory encodedFunctionCall =
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(newImplementation), "");
        addressesToCall.push(address(dscProxy));
        values.push(0);
        functionCalls.push(encodedFunctionCall);

        uint256 proposalId = hkdce.propose(addressesToCall, values, functionCalls, description);
        console2.log("Proposal state:", uint256(hkdce.state(proposalId)));

        vm.warp(block.timestamp + votingDelay + 1);
        vm.roll(block.number + votingDelay + 1);

        console2.log("Proposal state:", uint256(hkdce.state(proposalId)));

        // 2. vote on the proposal
        string memory voteReason = "healer Mike";
        // Inside of GovernorCountingSimple.sol, the vote type is defined as follows:
        // enum VoteType {
        // Against, // 0
        // For, // 1
        // Abstain // 2
        // }
        uint8 voteType = 1;
        hkdce.castVoteWithReason(proposalId, voteType, voteReason);

        vm.warp(block.timestamp + votingPeriod + 1);
        vm.roll(block.number + votingPeriod + 1);

        console2.log("Proposal state:", uint256(hkdce.state(proposalId)));

        // 3. queue the proposal
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        hkdce.queue(addressesToCall, values, functionCalls, descriptionHash);

        vm.warp(block.timestamp + minDelay + 1);
        vm.roll(block.number + minDelay + 1);

        console2.log("Proposal state:", uint256(hkdce.state(proposalId)));

        hkdce.execute(addressesToCall, values, functionCalls, descriptionHash);

        assertEq(dscProxy.version(), 2);

        console2.log("Proposal state:", uint256(hkdce.state(proposalId)));
    }
}
