// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig hc = new HelperConfig();
        (
            address wEthUsdPriceFeed,
            address wBtcUsdPriceFeed,
            address wEth,
            address wBtc,
            uint256 deployerKey
        ) = hc.activeNetworkConfig();
        tokenAddresses = [wEth, wBtc];
        priceFeedAddresses = [wEthUsdPriceFeed, wBtcUsdPriceFeed];
        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
        dsc.transferOwnership(address(engine)); // yang own DSC hanyalah engine, transferOwnership untuk transfer kepemilikan
        vm.stopBroadcast();
        return (dsc, engine, hc);
    }
}
