// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol, HKDCEngine, DSC, HelperConfig} from "script/deploy/deployProtocol.s.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    HKDCEngine public hkdce;
    DSC public dscProxy;
    HelperConfig public helperConfig;
    IERC20 public weth;
    IERC20 public wbtc;
    Handler public handler;
    address public constant NATIVE_TOKEN = address(0);
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    function setUp() public {
        // forked environment will make the fuzzing run super slow
        // vm.createSelectFork(vm.envString("ETH_RPC_URL"), 22507556);
        (hkdce, dscProxy,,,, helperConfig) = new DeployProtocol().run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        weth = IERC20(config.weth);
        wbtc = IERC20(config.wbtc);
        handler = new Handler(hkdce, dscProxy);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreDscThanCollateralHkdValue() public view {
        uint256 totalSupply = dscProxy.totalSupply();
        uint256 ethDeposited = address(hkdce).balance;
        uint256 wethDeposited = weth.balanceOf(address(hkdce));
        uint256 wbtcDeposited = wbtc.balanceOf(address(hkdce));

        uint256 ethHkdValue = hkdce.convertUsdToHkd(hkdce.getUsdValue(NATIVE_TOKEN, ethDeposited));
        uint256 wethHkdValue = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(weth), wethDeposited));
        uint256 wbtcHkdValue = hkdce.convertUsdToHkd(hkdce.getUsdValue(address(wbtc), wbtcDeposited));

        uint256 totalHkdValue = ethHkdValue + wethHkdValue + wbtcHkdValue;
        assertGe(totalHkdValue, totalSupply);
        console2.log("total runs for depositCollateral() function: ", handler.depositCollateralRuns());
        console2.log("total runs for mintDsc() function: ", handler.mintDscRuns());
    }

    function invariant_gettersCannotRevert() public view {
        hkdce.getNumOfCollateralTokens();
        hkdce.getDscToCollateralRatio(msg.sender);
        hkdce.shouldLiquidate(msg.sender);

        hkdce.getUsdValue(NATIVE_TOKEN, MAX_DEPOSIT_SIZE);
        hkdce.getUsdValue(address(weth), MAX_DEPOSIT_SIZE);
        hkdce.getUsdValue(address(wbtc), MAX_DEPOSIT_SIZE);

        hkdce.HKDC();
        hkdce.protocolFeeRecipient();
        hkdce.MIN_MINTABLE_AMOUNT();
        hkdce.collateralDeposited(msg.sender, NATIVE_TOKEN);
        hkdce.collateralDeposited(msg.sender, address(weth));
        hkdce.collateralDeposited(msg.sender, address(wbtc));
    }
}
