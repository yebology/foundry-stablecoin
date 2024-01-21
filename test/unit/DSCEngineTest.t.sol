// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig hc;

    address ethUsdPriceFeed;
    address wEth;
    address public USER = makeAddr("user");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, hc) = deployer.run();
        (ethUsdPriceFeed, , wEth, , ) = hc.activeNetworkConfig();
        ERC20Mock(wEth).mint(USER, STARTING_BALANCE);
    }

    function testGetUSDValue() public {
        uint256 ethAmount = 15e18; // 15 ETH tapi dalam wei
        uint256 expectedUSD = 30000e18; // 1 ETH $2000
        uint256 actualUSD = engine.getUSDValue(wEth, ethAmount);
        assertEq(actualUSD, expectedUSD);
    }

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(wEth, 0);
        vm.stopPrank();
    }
}
