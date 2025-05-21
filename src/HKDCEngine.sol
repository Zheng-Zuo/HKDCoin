// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DSC} from "./DSC.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FullMath} from "./libraries/FullMath.sol";

contract HKDCEngine is ReentrancyGuard {
    using OracleLib for AggregatorV3Interface;
    using SafeERC20 for IERC20;
    using SafeTransferLib for address;

    error ArrayLengthMismatch();
    error ZeroAmount();
    error TokenNotAllowed();
    error ExceedMaxDscMintable();
    error BelowMinDscMintableThreshold();
    error InsufficientEthCollateral();
    error InsufficientMintFee();
    error InsufficientEthForDepositAndMint();
    error CollateralBelowLiquidationThreshold();
    error CollateralAboveLiquidationThreshold();
    error InsufficientCollateralToRedeem();
    error MoreThanDscMinted();

    event PriceFeedSet(address indexed collateralToken, address indexed priceFeed);
    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 indexed amount);
    event DscMinted(address indexed user, uint256 indexed amount, uint256 indexed mintFee);
    event CollateralRedeemed(address indexed from, address to, address indexed collateralToken, uint256 indexed amount);
    event DscBurned(uint256 indexed amount, address indexed onBehalfOf, address indexed dscFrom);
    event Liquidated(
        address indexed tokenAddress, address indexed onBehalfOf, uint256 indexed debtToCover, uint256 RedeemedAmount
    );

    struct PriceFeedInfo {
        address priceFeed;
        uint256 priceFeedPrecision;
        uint256 tokenPrecision;
    }

    // list of allowed collateral tokens
    address[] public collateralTokens;
    // mapping of collateral token to price feed
    mapping(address collateralToken => PriceFeedInfo priceFeedInfo) public priceFeedInfos;
    // mapping of user to collateral token to amount deposited
    mapping(address user => mapping(address collateralToken => uint256 amount)) public collateralDeposited;
    // mapping of user to amount of dsc minted
    mapping(address user => uint256 amount) private _dscMinted;
    // DSC contract
    DSC public immutable HKDC;
    // protocol fee recipient
    address public protocolFeeRecipient;
    // USD Precision
    uint256 private constant PRECISION = 1e18;
    // USD-HKD ratio, denominator is 100
    uint256 private constant USD_HKD_RATIO = 780;
    // max dsc mintable per collateral hkd value ratio, denominator is 100
    uint256 private constant MAX_MINTABLE_RATIO = 60;
    // liquidation threshold, denominator is 100
    uint256 private constant LIQUIDATION_THRESHOLD_RATIO = 85;
    // min dsc mintable threshold
    uint256 public constant MIN_MINTABLE_AMOUNT = 5 * PRECISION;
    // mint fee ratio, denominator is 1000
    uint256 private constant MINT_FEE_RATIO = 3;
    // native token address
    address private constant NATIVE_TOKEN = address(0);
    // liquidition bonus ratio, denominator is 100
    uint256 private constant LIQUIDATION_BONUS_RATIO = 10;

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (priceFeedInfos[tokenAddress].priceFeed == address(0)) {
            revert TokenNotAllowed();
        }
        _;
    }

    modifier collateralAboveLiquidationThreshold(address user) {
        _;
        if (shouldLiquidate(user)) {
            revert CollateralBelowLiquidationThreshold();
        }
    }

    modifier triggerLiquidation(address user) {
        if (!shouldLiquidate(user)) {
            revert CollateralAboveLiquidationThreshold();
        }
        _;
    }

    constructor(
        address[] memory collateralTokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress,
        address protocolFeeRecipientAddress
    ) {
        _setCollateralTokens(collateralTokenAddresses, priceFeedAddresses);

        HKDC = DSC(dscAddress);
        protocolFeeRecipient = protocolFeeRecipientAddress;
    }

    function _setCollateralTokens(address[] memory collateralTokenAddresses, address[] memory priceFeedAddresses)
        private
    {
        if (collateralTokenAddresses.length != priceFeedAddresses.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < collateralTokenAddresses.length; i++) {
            address collateralToken = collateralTokenAddresses[i];
            address priceFeed = priceFeedAddresses[i];
            collateralTokens.push(collateralToken);
            uint256 priceFeedPrecision = 10 ** uint256(AggregatorV3Interface(priceFeed).decimals());
            uint256 tokenPrecision = PRECISION;
            if (collateralToken != NATIVE_TOKEN) {
                tokenPrecision = 10 ** uint256(IERC20Metadata(collateralToken).decimals());
            }
            priceFeedInfos[collateralToken] = PriceFeedInfo({
                priceFeed: priceFeed,
                priceFeedPrecision: priceFeedPrecision,
                tokenPrecision: tokenPrecision
            });
            emit PriceFeedSet(collateralToken, priceFeed);
        }
    }

    function depositCollateralAndMintDsc(address tokenAddress, uint256 collateralAmount, uint256 dscAmount)
        external
        payable
        isAllowedToken(tokenAddress)
        moreThanZero(collateralAmount)
    {
        if (tokenAddress == NATIVE_TOKEN) {
            collateralDeposited[msg.sender][tokenAddress] += collateralAmount;
            emit CollateralDeposited(msg.sender, tokenAddress, collateralAmount);

            (uint256 curMintAmount, uint256 mintFee) = _checkMintAmountAndFee(msg.sender, dscAmount);
            uint256 totalEthNeeded = collateralAmount + mintFee;

            if (msg.value < totalEthNeeded) {
                revert InsufficientEthForDepositAndMint();
            } else if (msg.value > totalEthNeeded) {
                msg.sender.safeTransferETH(msg.value - totalEthNeeded);
            }

            collateralDeposited[protocolFeeRecipient][NATIVE_TOKEN] += mintFee;
            _dscMinted[msg.sender] += curMintAmount;
            HKDC.mint(msg.sender, curMintAmount);

            emit DscMinted(msg.sender, curMintAmount, mintFee);
        } else {
            depositCollateral(tokenAddress, collateralAmount);
            mintDsc(dscAmount);
        }
    }

    function depositCollateral(address tokenAddress, uint256 amount)
        public
        payable
        nonReentrant
        isAllowedToken(tokenAddress)
        moreThanZero(amount)
    {
        collateralDeposited[msg.sender][tokenAddress] += amount;
        if (tokenAddress != NATIVE_TOKEN) {
            IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            if (msg.value < amount) {
                revert InsufficientEthCollateral();
            } else if (msg.value > amount) {
                msg.sender.safeTransferETH(msg.value - amount);
            }
        }
        emit CollateralDeposited(msg.sender, tokenAddress, amount);
    }

    function mintDsc(uint256 amount) public payable nonReentrant moreThanZero(amount) {
        (uint256 curMintAmount, uint256 mintFee) = _checkMintAmountAndFee(msg.sender, amount);
        if (msg.value < mintFee) {
            revert InsufficientMintFee();
        } else if (msg.value > mintFee) {
            msg.sender.safeTransferETH(msg.value - mintFee);
        }
        collateralDeposited[protocolFeeRecipient][NATIVE_TOKEN] += mintFee;
        _dscMinted[msg.sender] += curMintAmount;
        HKDC.mint(msg.sender, curMintAmount);
        emit DscMinted(msg.sender, curMintAmount, mintFee);
    }

    function _checkMintAmountAndFee(address account, uint256 amount) private view returns (uint256, uint256) {
        uint256 curMintAmount = 0;
        uint256 maxDscMintableLeft = getMaxDscMintableLeft(account);
        if (amount == type(uint256).max) {
            curMintAmount = maxDscMintableLeft;
        } else {
            if (amount > maxDscMintableLeft) {
                revert ExceedMaxDscMintable();
            }
            curMintAmount = amount;
        }

        if (curMintAmount < MIN_MINTABLE_AMOUNT) {
            revert BelowMinDscMintableThreshold();
        }

        uint256 mintFee = getMintFee(curMintAmount);
        return (curMintAmount, mintFee);
    }

    function burnDscAndRedeemCollateral(address tokenAddress, uint256 collateralAmount, uint256 dscAmount)
        external
        nonReentrant
        isAllowedToken(tokenAddress)
        moreThanZero(collateralAmount)
        moreThanZero(dscAmount)
        collateralAboveLiquidationThreshold(msg.sender)
    {
        _burnDsc(dscAmount, msg.sender, msg.sender);
        _redeemCollateral(tokenAddress, collateralAmount, msg.sender, msg.sender);
    }

    function redeemCollateral(address tokenAddress, uint256 collateralAmount)
        external
        nonReentrant
        isAllowedToken(tokenAddress)
        moreThanZero(collateralAmount)
        collateralAboveLiquidationThreshold(msg.sender)
    {
        _redeemCollateral(tokenAddress, collateralAmount, msg.sender, msg.sender);
    }

    function _redeemCollateral(address tokenAddress, uint256 collateralAmount, address from, address to) private {
        if (collateralAmount > collateralDeposited[from][tokenAddress]) {
            revert InsufficientCollateralToRedeem();
        }
        collateralDeposited[from][tokenAddress] -= collateralAmount;
        if (tokenAddress != NATIVE_TOKEN) {
            IERC20(tokenAddress).safeTransfer(to, collateralAmount);
        } else {
            to.safeTransferETH(collateralAmount);
        }
        emit CollateralRedeemed(from, to, tokenAddress, collateralAmount);
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        if (amountDscToBurn > _dscMinted[onBehalfOf]) {
            revert MoreThanDscMinted();
        }
        _dscMinted[onBehalfOf] -= amountDscToBurn;
        IERC20(address(HKDC)).safeTransferFrom(dscFrom, address(this), amountDscToBurn);
        HKDC.burn(amountDscToBurn);
        emit DscBurned(amountDscToBurn, onBehalfOf, dscFrom);
    }

    function burnDsc(uint256 amount) external moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
    }

    function liquidate(address tokenAddress, address onBehalfOf, uint256 debtToCover)
        external
        nonReentrant
        triggerLiquidation(onBehalfOf)
        isAllowedToken(tokenAddress)
        moreThanZero(debtToCover)
    {
        uint256 debtUsdValue = convertHkdToUsd(debtToCover);
        uint256 tokenAmount = getTokenAmountFromUsd(tokenAddress, debtUsdValue);
        uint256 bonusAmount = tokenAmount * LIQUIDATION_BONUS_RATIO / 100;
        uint256 totalRedeemableAmount = tokenAmount + bonusAmount;

        _burnDsc(debtToCover, onBehalfOf, msg.sender);
        _redeemCollateral(tokenAddress, totalRedeemableAmount, onBehalfOf, msg.sender);
        emit Liquidated(tokenAddress, onBehalfOf, debtToCover, totalRedeemableAmount);
    }

    function getUsdValue(address tokenAddress, uint256 amount)
        public
        view
        isAllowedToken(tokenAddress)
        returns (uint256)
    {
        PriceFeedInfo memory priceFeedInfo = priceFeedInfos[tokenAddress];
        (, int256 price,,,) = AggregatorV3Interface(priceFeedInfo.priceFeed).staleCheckLatestRoundData();
        uint256 numerator = uint256(price) * amount * PRECISION;
        uint256 denominator = priceFeedInfo.priceFeedPrecision * priceFeedInfo.tokenPrecision;
        return numerator / denominator;
    }

    function getTokenAmountFromUsd(address tokenAddress, uint256 usdValue)
        public
        view
        isAllowedToken(tokenAddress)
        returns (uint256)
    {
        PriceFeedInfo memory priceFeedInfo = priceFeedInfos[tokenAddress];
        (, int256 price,,,) = AggregatorV3Interface(priceFeedInfo.priceFeed).staleCheckLatestRoundData();
        uint256 numerator = usdValue * priceFeedInfo.priceFeedPrecision * priceFeedInfo.tokenPrecision;
        uint256 denominator = uint256(price) * PRECISION;
        return numerator / denominator;
    }

    function convertUsdToHkd(uint256 usdValue) public pure returns (uint256) {
        return FullMath.mulDiv(usdValue, USD_HKD_RATIO, 100);
    }

    function convertHkdToUsd(uint256 hkdValue) public pure returns (uint256) {
        return FullMath.mulDiv(hkdValue, 100, USD_HKD_RATIO);
    }

    function getMintFee(uint256 hkdValue) public view returns (uint256) {
        uint256 mintFeeInHkd = FullMath.mulDivRoundingUp(hkdValue, MINT_FEE_RATIO, 1000);
        uint256 mintFeeInUsd = convertHkdToUsd(mintFeeInHkd);
        uint256 mintFeeInWei = getTokenAmountFromUsd(NATIVE_TOKEN, mintFeeInUsd);
        return mintFeeInWei;
    }

    function getUserCollateralUsdValue(address user) public view returns (uint256) {
        uint256 totalUsdValue = 0;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address collateralToken = collateralTokens[i];
            uint256 amount = collateralDeposited[user][collateralToken];
            uint256 usdValue = getUsdValue(collateralToken, amount);
            totalUsdValue += usdValue;
        }
        return totalUsdValue;
    }

    function getUserCollateralHkdValue(address user) public view returns (uint256) {
        uint256 totalUsdValue = getUserCollateralUsdValue(user);
        return convertUsdToHkd(totalUsdValue);
    }

    function getAccountInfo(address user) public view returns (uint256, uint256) {
        uint256 dscMinted = _dscMinted[user];
        uint256 collateralHkdValue = getUserCollateralHkdValue(user);
        return (dscMinted, collateralHkdValue);
    }

    function getMaxDscMintable(address user) public view returns (uint256) {
        uint256 totalCollateralHkdValue = getUserCollateralHkdValue(user);
        uint256 maxDscMintable = totalCollateralHkdValue * MAX_MINTABLE_RATIO / 100;
        return maxDscMintable;
    }

    function getMaxDscMintableLeft(address user) public view returns (uint256) {
        uint256 maxDscMintable = getMaxDscMintable(user);
        uint256 mintedAmount = _dscMinted[user];
        if (maxDscMintable > mintedAmount) {
            return maxDscMintable - mintedAmount;
        } else {
            return 0;
        }
    }

    function getDscToCollateralRatio(address user) public view returns (uint256) {
        (uint256 dscMinted, uint256 collateralHkdValue) = getAccountInfo(user);
        uint256 dscToCollateralRatio = dscMinted * PRECISION / collateralHkdValue;
        return dscToCollateralRatio;
    }

    function shouldLiquidate(address user) public view returns (bool) {
        uint256 dscToCollateralRatio = getDscToCollateralRatio(user);
        uint256 liquidationRatio = LIQUIDATION_THRESHOLD_RATIO * PRECISION / 100;
        return dscToCollateralRatio >= liquidationRatio;
    }

    function getNumOfCollateralTokens() external view returns (uint256) {
        return collateralTokens.length;
    }

    receive() external payable {
        depositCollateral(NATIVE_TOKEN, msg.value);
    }
}
