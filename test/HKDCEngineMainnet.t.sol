// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DeployProtocol, HKDCEngine, DSC, HelperConfig} from "script/deploy/deployProtocol.s.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract HKDCEngineMainnetTest is Test {
    HKDCEngine public hkdce;
    DSC public dscProxy;
    HelperConfig public helperConfig;
    address public deployer;
    address public protocolFeeRecipient;
    IERC20 public weth;
    IERC20 public wbtc;
    address public ethPriceFeed;
    address public btcPriceFeed;
    address public user = makeAddr("user");
    uint256 constant BALANCE = 10000 ether;
    uint256 constant ONE_WBTC = 1e8;
    uint256 constant WBTC_BALANCE = 10000 * ONE_WBTC;
    uint256 public constant PRECISION = 1e18;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 22507556);
        (hkdce, dscProxy,,,, helperConfig) = new DeployProtocol().run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        deployer = vm.addr(config.deployerKey);
        protocolFeeRecipient = config.protocolFeeRecipient;
        weth = IERC20(config.weth);
        wbtc = IERC20(config.wbtc);
        ethPriceFeed = config.wethUsdPriceFeed;
        btcPriceFeed = config.wbtcUsdPriceFeed;

        deal(user, BALANCE);
        deal(address(weth), user, BALANCE);
        deal(address(wbtc), user, WBTC_BALANCE);

        vm.startPrank(user);
        weth.approve(address(hkdce), type(uint256).max);
        wbtc.approve(address(hkdce), type(uint256).max);
        dscProxy.approve(address(hkdce), type(uint256).max);
        vm.stopPrank();
    }

    modifier onlyUser() {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function test_initialState() public view {
        assertEq(dscProxy.hasRole(dscProxy.UPGRADE_ROLE(), deployer), false);
        assertEq(dscProxy.hasRole(dscProxy.MINTER_ROLE(), address(hkdce)), true);
        assertEq(dscProxy.hasRole(dscProxy.BURNER_ROLE(), address(hkdce)), true);
        assertEq(dscProxy.version(), 1);
        assertEq(weth.decimals(), 18);
        assertEq(wbtc.decimals(), 8);
        assertEq(hkdce.getNumOfCollateralTokens(), 3);
        assertEq(hkdce.protocolFeeRecipient(), protocolFeeRecipient);
        assertEq(user.balance, BALANCE);
        assertEq(weth.balanceOf(user), BALANCE);
        assertEq(wbtc.balanceOf(user), WBTC_BALANCE);

        // price feed setup
        // eth price feed
        (address priceFeed, uint256 priceFeedPrecision, uint256 tokenPrecision) = hkdce.priceFeedInfos(address(0));
        assertEq(priceFeed, ethPriceFeed);
        assertEq(priceFeedPrecision, 1e8);
        assertEq(tokenPrecision, 1e18);

        // weth price feed
        (priceFeed, priceFeedPrecision, tokenPrecision) = hkdce.priceFeedInfos(address(weth));
        assertEq(priceFeed, ethPriceFeed);
        assertEq(priceFeedPrecision, 1e8);
        assertEq(tokenPrecision, 1e18);

        // wbtc price feed
        (priceFeed, priceFeedPrecision, tokenPrecision) = hkdce.priceFeedInfos(address(wbtc));
        assertEq(priceFeed, btcPriceFeed);
        assertEq(priceFeedPrecision, 1e8);
        assertEq(tokenPrecision, 1e8);
    }

    function test_getUsdValue() public view {
        uint256 ethAmount = 1 ether;
        uint256 ethUsdValue = hkdce.getUsdValue(address(weth), ethAmount);
        console2.log("ethUsdValue", ethUsdValue / PRECISION);

        uint256 btcAmount = 1 * 10 ** wbtc.decimals();
        uint256 btcUsdValue = hkdce.getUsdValue(address(wbtc), btcAmount);
        console2.log("btcUsdValue", btcUsdValue / PRECISION);
    }

    function test_getHkdValue() public view {
        uint256 ethAmount = 1 ether;
        uint256 ethUsdValue = hkdce.getUsdValue(address(weth), ethAmount);
        uint256 ethHkdValue = hkdce.convertUsdToHkd(ethUsdValue);
        console2.log("ethHkdValue", ethHkdValue / PRECISION);

        uint256 btcAmount = 1 * 10 ** wbtc.decimals();
        uint256 btcUsdValue = hkdce.getUsdValue(address(wbtc), btcAmount);
        uint256 btcHkdValue = hkdce.convertUsdToHkd(btcUsdValue);
        console2.log("btcHkdValue", btcHkdValue / PRECISION);
    }

    function test_directDepositEthAndMintSeparately() public onlyUser {
        uint256 ethAmount = 1 ether;
        (bool success,) = address(hkdce).call{value: ethAmount}("");
        assertEq(success, true);
        assertEq(user.balance, BALANCE - ethAmount);
        assertEq(address(hkdce).balance, ethAmount);

        uint256 recordedEthAmount = hkdce.collateralDeposited(user, address(0));
        assertEq(recordedEthAmount, ethAmount);

        uint256 expectedCollateralHkdValue = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(0), recordedEthAmount));
        uint256 collateralHkdValue = hkdce.getUserCollateralHkdValue(user);
        assertEq(collateralHkdValue, expectedCollateralHkdValue);

        uint256 maxMintableLeft = hkdce.getMaxDscMintableLeft(user);
        assertEq(maxMintableLeft, collateralHkdValue * 60 / 100);

        uint256 mintFee = hkdce.getMintFee(maxMintableLeft);

        hkdce.mintDsc{value: mintFee}(type(uint256).max);
        assertEq(dscProxy.balanceOf(user), maxMintableLeft);
    }

    function test_depositCollateralWithWethAndMintSeparately() public onlyUser {
        uint256 wethAmount = 1 ether;
        hkdce.depositCollateral(address(weth), wethAmount);
        assertEq(weth.balanceOf(user), BALANCE - wethAmount);
        assertEq(weth.balanceOf(address(hkdce)), wethAmount);

        uint256 recordedWethAmount = hkdce.collateralDeposited(user, address(weth));
        assertEq(recordedWethAmount, wethAmount);

        uint256 expectedCollateralHkdValue = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(weth), recordedWethAmount));
        uint256 collateralHkdValue = hkdce.getUserCollateralHkdValue(user);
        assertEq(collateralHkdValue, expectedCollateralHkdValue);

        uint256 maxMintableLeft = hkdce.getMaxDscMintableLeft(user);
        assertEq(maxMintableLeft, collateralHkdValue * 60 / 100);

        uint256 mintFee = hkdce.getMintFee(maxMintableLeft);

        hkdce.mintDsc{value: mintFee}(type(uint256).max);
        assertEq(dscProxy.balanceOf(user), maxMintableLeft);
    }

    function test_depositCollateralWithWbtcAndMintSeparately() public onlyUser {
        hkdce.depositCollateral(address(wbtc), ONE_WBTC);
        assertEq(wbtc.balanceOf(user), WBTC_BALANCE - ONE_WBTC);
        assertEq(wbtc.balanceOf(address(hkdce)), ONE_WBTC);

        uint256 recordedWbtcAmount = hkdce.collateralDeposited(user, address(wbtc));
        assertEq(recordedWbtcAmount, ONE_WBTC);

        uint256 expectedCollateralHkdValue = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), recordedWbtcAmount));
        uint256 collateralHkdValue = hkdce.getUserCollateralHkdValue(user);
        assertEq(collateralHkdValue, expectedCollateralHkdValue);

        uint256 maxMintableLeft = hkdce.getMaxDscMintableLeft(user);
        assertEq(maxMintableLeft, collateralHkdValue * 60 / 100);

        uint256 mintFee = hkdce.getMintFee(maxMintableLeft);

        hkdce.mintDsc{value: mintFee}(type(uint256).max);
        assertEq(dscProxy.balanceOf(user), maxMintableLeft);
    }

    function test_revertWithNotAllowedCollateralToken() public onlyUser {
        IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        vm.expectRevert(HKDCEngine.TokenNotAllowed.selector);
        hkdce.depositCollateral(address(usdc), 1);
    }

    function test_revertWithInSufficientCollateralAmount() public onlyUser {
        uint256 ethAmount = 1 ether;
        vm.expectRevert(HKDCEngine.InsufficientEthCollateral.selector);
        hkdce.depositCollateral{value: ethAmount - 1}(address(0), ethAmount);
    }

    function test_revertWithInSufficientMintFeeAmount() public onlyUser {
        uint256 ethAmount = 1 ether;

        hkdce.depositCollateral{value: ethAmount}(address(0), ethAmount);

        uint256 maxMintableLeft = hkdce.getMaxDscMintableLeft(user);
        uint256 mintFee = hkdce.getMintFee(maxMintableLeft);
        vm.expectRevert(HKDCEngine.InsufficientMintFee.selector);
        hkdce.mintDsc{value: mintFee - 1}(maxMintableLeft);
    }

    function test_revertWithInSufficientEthForDepositAndMint() public onlyUser {
        uint256 ethAmount = 1 ether;
        uint256 hkdcAmount = 1000 ether;
        uint256 mintFee = hkdce.getMintFee(hkdcAmount);
        vm.expectRevert(HKDCEngine.InsufficientEthForDepositAndMint.selector);
        hkdce.depositCollateralAndMintDsc{value: ethAmount + mintFee - 1}(address(0), ethAmount, hkdcAmount);
    }

    function test_depositCollateralAndMintDscWithEth() public onlyUser {
        uint256 ethAmount = 1 ether;
        uint256 hkdcAmount = 1000 ether;
        uint256 mintFee = hkdce.getMintFee(hkdcAmount);

        hkdce.depositCollateralAndMintDsc{value: ethAmount + mintFee}(address(0), ethAmount, hkdcAmount);

        assertEq(dscProxy.balanceOf(user), hkdcAmount);
        assertEq(hkdce.collateralDeposited(user, address(0)), ethAmount);
        assertEq(hkdce.collateralDeposited(protocolFeeRecipient, address(0)), mintFee);
    }

    function test_depositCollateralAndMintDscWithWbtc() public onlyUser {
        uint256 wbtcAmount = ONE_WBTC;
        uint256 expectedMaxHkdcMintable = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcAmount)) * 60 / 100;
        uint256 mintFee = hkdce.getMintFee(expectedMaxHkdcMintable);

        hkdce.depositCollateralAndMintDsc{value: mintFee}(address(wbtc), wbtcAmount, type(uint256).max);

        assertEq(dscProxy.balanceOf(user), expectedMaxHkdcMintable);
        assertEq(hkdce.collateralDeposited(user, address(wbtc)), wbtcAmount);
        assertEq(hkdce.collateralDeposited(protocolFeeRecipient, address(0)), mintFee);
    }

    function test_refundExcessEth() public onlyUser {
        uint256 wbtcAmount = ONE_WBTC;
        uint256 expectedMaxHkdcMintable = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcAmount)) * 60 / 100;
        uint256 mintFee = hkdce.getMintFee(expectedMaxHkdcMintable);

        hkdce.depositCollateralAndMintDsc{value: mintFee * 2}(address(wbtc), wbtcAmount, type(uint256).max);

        assertEq(dscProxy.balanceOf(user), expectedMaxHkdcMintable);
        assertEq(hkdce.collateralDeposited(user, address(wbtc)), wbtcAmount);
        assertEq(hkdce.collateralDeposited(protocolFeeRecipient, address(0)), mintFee);
        assertEq(user.balance, BALANCE - mintFee);
    }

    function test_revertWithExceedMaxDscMintable() public onlyUser {
        uint256 wbtcAmount = ONE_WBTC;
        uint256 expectedMaxHkdcMintable = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcAmount)) * 60 / 100;
        uint256 mintFee = hkdce.getMintFee(expectedMaxHkdcMintable);
        vm.expectRevert(HKDCEngine.ExceedMaxDscMintable.selector);
        hkdce.depositCollateralAndMintDsc{value: mintFee}(address(wbtc), wbtcAmount, expectedMaxHkdcMintable + 1);
    }

    function test_revertWithBelowMinDscMintableThreshold() public onlyUser {
        uint256 wbtcAmount = ONE_WBTC;
        uint256 mintAmount = 5 ether - 1;
        uint256 mintFee = hkdce.getMintFee(mintAmount);
        vm.expectRevert(HKDCEngine.BelowMinDscMintableThreshold.selector);
        hkdce.depositCollateralAndMintDsc{value: mintFee}(address(wbtc), wbtcAmount, mintAmount);
    }

    function test_revertWithMoreThanDscMinted() public onlyUser {
        uint256 wbtcAmount = ONE_WBTC;
        uint256 expectedMaxHkdcMintable = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcAmount)) * 60 / 100;
        uint256 mintFee = hkdce.getMintFee(expectedMaxHkdcMintable);

        hkdce.depositCollateralAndMintDsc{value: mintFee}(address(wbtc), wbtcAmount, type(uint256).max);
        vm.expectRevert(HKDCEngine.MoreThanDscMinted.selector);
        hkdce.burnDsc(expectedMaxHkdcMintable + 1);
    }

    function test_burnDsc() public onlyUser {
        uint256 wbtcAmount = ONE_WBTC;
        uint256 expectedMaxHkdcMintable = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcAmount)) * 60 / 100;
        uint256 mintFee = hkdce.getMintFee(expectedMaxHkdcMintable);

        hkdce.depositCollateralAndMintDsc{value: mintFee}(address(wbtc), wbtcAmount, type(uint256).max);
        assertEq(dscProxy.balanceOf(user), expectedMaxHkdcMintable);
        (uint256 dscMinted,) = hkdce.getAccountInfo(user);
        assertEq(dscMinted, expectedMaxHkdcMintable);

        hkdce.burnDsc(expectedMaxHkdcMintable);
        assertEq(dscProxy.balanceOf(user), 0);

        (dscMinted,) = hkdce.getAccountInfo(user);
        assertEq(dscMinted, 0);
    }

    function test_revertWithInsufficientCollateralToRedeem() public onlyUser {
        uint256 wbtcAmount = ONE_WBTC;
        uint256 expectedMaxHkdcMintable = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcAmount)) * 60 / 100;
        uint256 mintFee = hkdce.getMintFee(expectedMaxHkdcMintable);

        hkdce.depositCollateralAndMintDsc{value: mintFee}(address(wbtc), wbtcAmount, type(uint256).max);
        vm.expectRevert(HKDCEngine.InsufficientCollateralToRedeem.selector);
        hkdce.redeemCollateral(address(wbtc), wbtcAmount + 1);
    }

    function test_revertWithCollateralBelowLiquidationThreshold() public onlyUser {
        uint256 wbtcAmount = ONE_WBTC;
        uint256 expectedMaxHkdcMintable = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcAmount)) * 60 / 100;
        uint256 mintFee = hkdce.getMintFee(expectedMaxHkdcMintable);

        hkdce.depositCollateralAndMintDsc{value: mintFee}(address(wbtc), wbtcAmount, type(uint256).max);
        vm.expectRevert(HKDCEngine.CollateralBelowLiquidationThreshold.selector);
        hkdce.redeemCollateral(address(wbtc), wbtcAmount);
    }

    function test_redeemCollateral() public onlyUser {
        uint256 wbtcAmount = ONE_WBTC;
        uint256 expectedMaxHkdcMintable = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcAmount)) * 60 / 100;
        uint256 mintFee = hkdce.getMintFee(expectedMaxHkdcMintable);

        hkdce.depositCollateralAndMintDsc{value: mintFee}(address(wbtc), wbtcAmount, type(uint256).max);
        // console2.log("expectedMaxHkdcMintable", expectedMaxHkdcMintable);

        uint256 minHkdValueForCollateral = expectedMaxHkdcMintable * 100 / 85;
        uint256 minUsdValueForCollateral = hkdce.convertHkdToUsd(minHkdValueForCollateral);
        uint256 minCollateralAmount = hkdce.getTokenAmountFromUsd(address(wbtc), minUsdValueForCollateral);

        // console2.log("minHkdValueForCollateral", minHkdValueForCollateral);
        // console2.log("minCollateralAmount", minCollateralAmount);
        // console2.log(
        //     "recalculated minHkdValueForCollateral",
        //     hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), minCollateralAmount))
        // );

        uint256 redeemAmount = wbtcAmount - (minCollateralAmount) - 100;
        // console2.log("redeemAmount", redeemAmount);
        hkdce.redeemCollateral(address(wbtc), redeemAmount);
        uint256 finalRatio = hkdce.getDscToCollateralRatio(user);
        assertLt(finalRatio, 85 * 1e18 / 100);
        // console2.log("finalRatio", finalRatio);
    }

    function test_burnDscAndRedeemCollateral() public onlyUser {
        uint256 initialWbtcBalance = wbtc.balanceOf(user);

        uint256 wbtcAmount = ONE_WBTC;
        uint256 expectedMaxHkdcMintable = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcAmount)) * 60 / 100;
        uint256 mintFee = hkdce.getMintFee(expectedMaxHkdcMintable);

        hkdce.depositCollateralAndMintDsc{value: mintFee}(address(wbtc), wbtcAmount, type(uint256).max);
        assertEq(dscProxy.balanceOf(user), expectedMaxHkdcMintable);
        assertEq(wbtc.balanceOf(user), initialWbtcBalance - wbtcAmount);

        hkdce.burnDscAndRedeemCollateral(address(wbtc), wbtcAmount, expectedMaxHkdcMintable);
        assertEq(wbtc.balanceOf(user), initialWbtcBalance);
        assertEq(hkdce.collateralDeposited(user, address(wbtc)), 0);
        assertEq(dscProxy.balanceOf(user), 0);
    }
}
