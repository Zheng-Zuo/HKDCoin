// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {HKDCEngine, DSC} from "script/deploy/deployProtocol.s.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Handler is Test {
    HKDCEngine public hkdce;
    DSC public dscProxy;
    IERC20 public weth;
    IERC20 public wbtc;
    address[] public depositedUsers;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address public constant NATIVE_TOKEN = address(0);

    uint256 public constant MIN_MINT_AMOUNT = 5 ether;

    // check runs
    uint256 public depositCollateralRuns;
    uint256 public mintDscRuns;

    constructor(HKDCEngine _hkdce, DSC _dscProxy) {
        hkdce = _hkdce;
        dscProxy = _dscProxy;

        weth = IERC20(hkdce.collateralTokens(1));
        wbtc = IERC20(hkdce.collateralTokens(2));
    }

    modifier onlySender() {
        vm.startPrank(msg.sender);
        _;
        vm.stopPrank();
    }

    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) external onlySender {
        (address collateralToken, uint256 amount) = _airdropToken(collateralSeed, collateralAmount);
        if (collateralToken != NATIVE_TOKEN) {
            IERC20(collateralToken).approve(address(hkdce), amount);
            hkdce.depositCollateral(collateralToken, amount);
        } else {
            hkdce.depositCollateral{value: amount}(collateralToken, amount);
        }

        depositedUsers.push(msg.sender);
        depositCollateralRuns++;
    }

    function mintDsc(uint256 amount) external {
        address user = _getValidDepositor();
        if (user == address(0)) {
            return;
        }
        vm.startPrank(user);
        uint256 maxDscMintableLeft = hkdce.getMaxDscMintableLeft(user);
        vm.assume(MIN_MINT_AMOUNT <= amount && amount <= maxDscMintableLeft);
        uint256 mintFee = hkdce.getMintFee(amount);
        deal(user, mintFee);
        hkdce.mintDsc{value: mintFee}(amount);
        vm.stopPrank();
        
        mintDscRuns++;
    }

    function _getCollateralTokenFromSeed(uint256 collateralSeed) private view returns (address) {
        uint256 index = collateralSeed % 3;
        if (index == 0) return NATIVE_TOKEN;
        if (index == 1) return address(weth);
        return address(wbtc);
    }

    function _airdropToken(uint256 collateralSeed, uint256 collateralAmount) private returns (address, uint256) {
        address collateralToken = _getCollateralTokenFromSeed(collateralSeed);
        collateralAmount = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);
        console2.log("final amount", collateralAmount);

        if (collateralToken == NATIVE_TOKEN) {
            deal(msg.sender, collateralAmount);
        } else {
            deal(collateralToken, msg.sender, collateralAmount);
        }
        return (collateralToken, collateralAmount);
    }

    function _getValidDepositor() private view returns (address) {
        if (depositedUsers.length == 0) {
            return address(0);
        }
        uint256 num = uint256(uint160(msg.sender));
        uint256 index = num % depositedUsers.length;
        return depositedUsers[index];
    }
}
