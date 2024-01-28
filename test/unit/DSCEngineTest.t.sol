// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {SafeMath} from "lib/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig hc;

    using SafeMath for uint256;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public wEth;
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT_DSC = 1 ether;
    uint256 public constant AMOUNT_TO_BURN = 0.005 ether;
    uint256 public constant STARTING_BALANCE = 10 ether;

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(wEth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier prepareToRevertZeroException() {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        _;
    }

    modifier mintDSC() {
        vm.startPrank(USER);
        engine.mintDSC(AMOUNT_TO_MINT_DSC);
        vm.stopPrank();
        _;
    }

    modifier mintDSCToLiquidatePosition() {
        vm.startPrank(USER);
        engine.mintDSC(muchDSCToMint);
        vm.stopPrank();
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, hc) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, wEth, , ) = hc.activeNetworkConfig();
        ERC20Mock(wEth).mint(USER, STARTING_BALANCE);
    }

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(wEth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testGetUSDValue() public {
        uint256 ethAmount = 15e18; // 15 ETH tapi dalam wei
        uint256 expectedUSD = 30000e18; // 1 ETH $2000
        uint256 actualUSD = engine.getUSDValue(wEth, ethAmount);
        assertEq(actualUSD, expectedUSD);
    }

    function testGetTokenAmountFromUSD() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUSD(wEth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(wEth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock(
            "RAND",
            "RAND",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD) = engine
            .getAccountInformation(USER);
        uint256 expectedTotalDSCMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUSD(
            wEth,
            totalCollateralValueInUSD
        );
        assertEq(totalDSCMinted, expectedTotalDSCMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testCanMintDSCAfterDeposit() public depositedCollateral mintDSC {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine
            .getAccountInformation(USER);
        uint256 expectedDSCMinted = 1e18;
        assertEq(totalDSCMinted, expectedDSCMinted);
    }

    function testCanBurnDSCForRedeem() public depositedCollateral mintDSC {
        vm.startPrank(USER);
        (uint256 recentDSCMinted, uint256 recentCollateralValueInUSD) = engine
            .getAccountInformation(USER);
        uint256 wEthDeposited = ERC20Mock(wEth).balanceOf(address(engine));
        dsc.approve(address(engine), AMOUNT_TO_MINT_DSC);
        engine.redeemCollateralForDSC(
            wEth,
            AMOUNT_TO_MINT_DSC,
            AMOUNT_TO_BURN
        );
        (uint256 latestDSCMinted, uint256 latestCollateralValueInUSD) = engine
            .getAccountInformation(USER);
        vm.stopPrank();
        assert(recentDSCMinted != latestDSCMinted);
        assert(recentCollateralValueInUSD != latestCollateralValueInUSD);
    }

    function testCannotMintZeroDSC()
        public
        depositedCollateral
        prepareToRevertZeroException
    {
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testCannotRedeemZeroCollateral()
        public
        depositedCollateral
        prepareToRevertZeroException
    {
        engine.redeemCollateral(wEth, 0);
        vm.stopPrank();
    }

    // function testCanLiquidateUser() public depositedCollateral mintDSCToLiquidatePosition {
    //     uint256 userHealthFactor = engine.getHealthFactor(USER);
    //     console.log(userHealthFactor);
    //     console.log(1e18);
    // }
}
