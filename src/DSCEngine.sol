// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // ini itu buat cegah supaya function e gabisa dihack
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// DSC harus selalu overcollateralized
// DSCEngine ini yang kontrol StableCoin
contract DSCEngine is ReentrancyGuard {

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__TokenAddressesAndPriceFeedMustBeSameLength();
    error DSCEngine__HealthFactorIsBelowMinimum(uint256 userHealthFactor);
    error DSCEngine__MintFailed();

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    address[] private s_collateralTokens; // wETH sama wBTC

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // batas ambang kerugian (dalam persen),
    // kalo udah capai kesana, bisa milih tindakan likuidasi
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] == priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeed[_token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    function depositCollateralAndMintDSC() external {}

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function burnDSC() external {}

    // cek apakah value collateralnya > DSC (collateral harus > DSC)
    // amountDSCToMint = jumlah DSC yang mau di mint
    function mintDSC(
        uint256 amountDSCToMint
    ) external moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        // cek siapa tahu mereka mint terlalu banyak misal (mint $150 dalam DSC padahal cuma punya $100 dalam ETH)
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    // kalo rasio likuidasinya dibawah 1, mereka bisa dapat likuidasi
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDSCMinted,
            uint256 collateralValueInUSD
        ) = _getAccountInformation(user);
        uint256 collateralAdjusted = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjusted * PRECISION) / totalDSCMinted;    
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
        return (totalDSCMinted, collateralValueInUSD);
    }

    // apakah mereka punya cukup collateral?
    // kalo ga, revert
    function revertIfHealthFactorIsBroken(address user) internal view {    
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBelowMinimum(userHealthFactor);
        }
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUSD) {
        // loop di tiap collateral token, cari berapa besar user deposit dan mappinglah buat dapetin USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (,int256 price, , ,) = priceFeed.latestRoundData();
        // misal 1ETH = $1000
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
        // -> uin256(price) bakal return dengan 8 decimal (karena eth dan btc gitu), lalu akan dikali dengan 10 decimal
        // karena amount akan berjumlah 1e18 (dalam wei), maka price harus diconvert menjadi 1e18 juga
        // supaya memudahkan perhitungan
    }
}
