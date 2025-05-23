// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DeployProtocol, HKDCEngine, DSC, HelperConfig} from "script/deploy/deployProtocol.s.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract HKDCEngineAnvilTest is Test {
    HKDCEngine public hkdce;
    DSC public dscProxy;
    HelperConfig public helperConfig;
    address public deployer;
    address public protocolFeeRecipient;
    IERC20 public weth;
    IERC20 public wbtc;
    MockV3Aggregator public ethPriceFeed;
    MockV3Aggregator public btcPriceFeed;
    address public user = makeAddr("user");
    address public helloWen = makeAddr("helloWen");
    uint256 constant BALANCE = 10000 ether;
    uint256 constant ONE_WBTC = 1e8;
    uint256 constant WBTC_BALANCE = 10000 * ONE_WBTC;
    uint256 public constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_BONUS_RATIO = 10;

    function setUp() public {
        (hkdce, dscProxy,,,, helperConfig) = new DeployProtocol().run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        deployer = vm.addr(config.deployerKey);
        protocolFeeRecipient = config.protocolFeeRecipient;
        weth = IERC20(config.weth);
        wbtc = IERC20(config.wbtc);
        ethPriceFeed = MockV3Aggregator(config.wethUsdPriceFeed);
        btcPriceFeed = MockV3Aggregator(config.wbtcUsdPriceFeed);

        deal(user, BALANCE);
        deal(address(weth), user, BALANCE);
        deal(address(wbtc), user, WBTC_BALANCE);

        deal(helloWen, BALANCE);
        deal(address(weth), helloWen, BALANCE);
        deal(address(wbtc), helloWen, WBTC_BALANCE);
        deal(address(dscProxy), helloWen, BALANCE);

        vm.startPrank(user);
        weth.approve(address(hkdce), type(uint256).max);
        wbtc.approve(address(hkdce), type(uint256).max);
        dscProxy.approve(address(hkdce), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(helloWen);
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

    modifier onlyHelloWen() {
        vm.startPrank(helloWen);
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
        assertEq(dscProxy.balanceOf(helloWen), BALANCE);

        // price feed setup
        // eth price feed
        (address priceFeed, uint256 priceFeedPrecision, uint256 tokenPrecision) = hkdce.priceFeedInfos(address(0));
        assertEq(priceFeed, address(ethPriceFeed));
        assertEq(priceFeedPrecision, 1e8);
        assertEq(tokenPrecision, 1e18);

        // weth price feed
        (priceFeed, priceFeedPrecision, tokenPrecision) = hkdce.priceFeedInfos(address(weth));
        assertEq(priceFeed, address(ethPriceFeed));
        assertEq(priceFeedPrecision, 1e8);
        assertEq(tokenPrecision, 1e18);

        // wbtc price feed
        (priceFeed, priceFeedPrecision, tokenPrecision) = hkdce.priceFeedInfos(address(wbtc));
        assertEq(priceFeed, address(btcPriceFeed));
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

    function test_dscToCollateralRatio() public onlyUser {
        uint256 ratio = hkdce.getDscToCollateralRatio(user);
        assertEq(ratio, 0);

        uint256 ethAmount = 1 ether;
        uint256 hkdcAmount = 1000 ether;
        uint256 mintFee = hkdce.getMintFee(hkdcAmount);

        hkdce.depositCollateralAndMintDsc{value: ethAmount + mintFee}(address(0), ethAmount, hkdcAmount);

        uint256 ethUsdValue = hkdce.getUsdValue(address(weth), ethAmount);
        uint256 ethHkdValue = hkdce.convertUsdToHkd(ethUsdValue);

        ratio = hkdce.getDscToCollateralRatio(user);
        assertEq(ratio, hkdcAmount * PRECISION / ethHkdValue);
        // console2.log("ratio", ratio);
        // console2.log("calculated ratio", hkdcAmount * PRECISION / ethHkdValue);
    }

    function test_revertWithShouldLiquidateIsFalse() public {
        uint256 ethAmount = 1 ether;
        uint256 hkdcAmount = 1000 ether;
        uint256 mintFee = hkdce.getMintFee(hkdcAmount);

        vm.startPrank(user);
        hkdce.depositCollateralAndMintDsc{value: ethAmount + mintFee}(address(0), ethAmount, hkdcAmount);
        vm.stopPrank();

        bool shouldLiquidate = hkdce.shouldLiquidate(user);
        assertEq(shouldLiquidate, false);

        vm.expectRevert(HKDCEngine.CollateralAboveLiquidationThreshold.selector);
        vm.startPrank(helloWen);
        hkdce.liquidate(address(0), user, 1);
        vm.stopPrank();
    }

    function test_liquidate() public {
        uint256 ethAmount = 1 ether;
        uint256 hkdcAmount = 1000 ether;
        uint256 mintFee = hkdce.getMintFee(hkdcAmount);

        vm.startPrank(user);
        hkdce.depositCollateralAndMintDsc{value: ethAmount + mintFee}(address(0), ethAmount, hkdcAmount);
        vm.stopPrank();

        bool shouldLiquidate = hkdce.shouldLiquidate(user);
        assertEq(shouldLiquidate, false);

        ethPriceFeed.updateAnswer(0);
        shouldLiquidate = hkdce.shouldLiquidate(user);
        assertEq(shouldLiquidate, true);

        uint256 ratio = hkdce.getDscToCollateralRatio(user);
        assertEq(ratio, type(uint256).max);

        ethPriceFeed.updateAnswer(150e8);
        shouldLiquidate = hkdce.shouldLiquidate(user);
        assertEq(shouldLiquidate, true);

        uint256 beforeRatio = hkdce.getDscToCollateralRatio(user);
        (uint256 beforeDscMinted, uint256 beforeCollateralDeposited) = hkdce.getAccountInfo(user);
        // console2.log("beforeRatio", beforeRatio);
        // console2.log("beforeDscMinted", beforeDscMinted);
        // console2.log("beforeCollateralDeposited", beforeCollateralDeposited);

        // liquidate the eth from user with 900 hkdc
        uint256 debtToCover = hkdcAmount;
        uint256 beforeEthBalance = helloWen.balance;
        // console2.log("beforeEthBalance", beforeEthBalance);

        vm.startPrank(helloWen);
        hkdce.liquidate(address(0), user, debtToCover);
        vm.stopPrank();

        uint256 afterEthBalance = helloWen.balance;
        assertGt(afterEthBalance, beforeEthBalance);

        assertEq(hkdce.shouldLiquidate(user), false);
        uint256 afterRatio = hkdce.getDscToCollateralRatio(user);
        assertLt(afterRatio, beforeRatio);

        (uint256 afterDscMinted, uint256 afterCollateralDeposited) = hkdce.getAccountInfo(user);
        assertLt(afterDscMinted, beforeDscMinted);
        assertLt(afterCollateralDeposited, beforeCollateralDeposited);
    }
}
