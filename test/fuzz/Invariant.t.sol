// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "../../test/fuzz/Handler.t.sol";

contract Invariant is StdInvariant, Test {
    //
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig hc;
    Handler handler;
    
    address wEth;
    address wBtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, hc) = deployer.run();
        (,,wEth,wBtc,) = hc.activeNetworkConfig();
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
        // targetContract(address(engine)); // biarin foundry ngelakuin wild check ke address contract itu
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(wEth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wBtc).balanceOf(address(engine));
        uint256 wEthValue = engine.getUSDValue(wEth, totalWethDeposited);
        uint256 wBtcValue = engine.getUSDValue(wBtc, totalWbtcDeposited);
        assert(wEthValue + wBtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotBeRevert() public view {

    }
    // 
}