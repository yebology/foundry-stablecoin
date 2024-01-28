// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol"; // ini itu buat cegah supaya function e gabisa dihack
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// DSC harus selalu overcollateralized
// DSCEngine ini yang kontrol StableCoin
contract DSCEngine is ReentrancyGuard {
    //
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__TokenAddressesAndPriceFeedMustBeSameLength();
    error DSCEngine__HealthFactorIsBelowMinimum(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

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
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // batas ambang kerugian (dalam persen),
    // kalo udah capai kesana, bisa milih tindakan likuidasi
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant AGGREGATOR_PRICE_NOW_ETH = 2000;

    ERC20Mock wEthMock;

    // done
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    // done
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    // done
    modifier isAllowedToken(address _token) {
        if (s_priceFeed[_token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    // done
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    // done
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
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

    // done
    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external {
        console.log(address(msg.sender));
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    // pakai nonReentrant karena kita bakal moving token biar ga dihack
    // done
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        revertIfHealthFactorIsBroken(msg.sender);
    }

    // done
    function burnDSC(uint256 amount) public {
        _burnDSC(amount, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    // cek apakah value collateralnya > DSC (collateral harus > DSC)
    // amountDSCToMint = jumlah DSC yang mau di mint
    // done
    function mintDSC(
        uint256 amountDSCToMint
    ) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        // cek siapa tahu mereka mint terlalu banyak misal (mint $150 dalam DSC padahal cuma punya $100 dalam ETH)
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function getDSCMinted() external view returns (uint256) {
        return s_DSCMinted[msg.sender];
    }

    // done
    function getTokenAmountFromUSD(
        address collateral,
        uint256 debtToCoverInWei
    ) public view returns (uint256 tokenAmount) {
        // 1 ETH = $2000 di mock, kalau $1000 berarti 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[collateral]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // ($10e18 * 1e18) / ($2000e8 * 1e10) = 0.5 ETH
        tokenAmount =
            (debtToCoverInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
        // price itu 8 decimal, perlu dikali add feed precision biar jadie 18 satuan
        return tokenAmount;
    }

    // user yang MIN_HEALTH_FACTOR < 1
    // debtToCover itu DSC yang mau di burn untuk improve healthfactor dari user
    // done
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        // burn DSC mereka (debt) dan ambil collateralnya
        // bad user : $140 di ETH, $100 di DSC
        // debtToCover : $100
        // $100 di DSC berapa di ETH ? -> 0.05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(
            collateral,
            debtToCover
        );
        // 10% bonus untuk liquidator
        // give $110 of wETHfor 100 DSC
        // 0.05 * 0.01 = 0.005 ETH (getting 0.055 ETH)
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        _burnDSC(debtToCover, user, msg.sender);
        // user adalah orang yang mau di paydown collateral debtnya
        // msg.sender or whoever called this function will paying down the
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    // kalo rasio likuidasinya dibawah 1, mereka bisa dapat likuidasi
    // done
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDSCMinted,
            uint256 collateralValueInUSD
        ) = _getAccountInformation(user);
        uint256 collateralAdjusted = (collateralValueInUSD *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjusted * PRECISION) / totalDSCMinted;
    }

    // done
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

    // done
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // done
    function _burnDSC(
        uint256 amountDSC,
        address whoseDSCAreWeBurnFor,
        address dscFrom
    ) private {
        s_DSCMinted[whoseDSCAreWeBurnFor] -= amountDSC;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDSC); // slaah disini kek e
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDSC);
    }

    // apakah mereka punya cukup collateral?
    // kalo ga, revert
    // done
    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBelowMinimum(userHealthFactor);
        }
    }

    // done
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

    // done
    function getUSDValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // misal 1ETH = $1000
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
        // -> uin256(price) bakal return dengan 8 decimal (karena eth dan btc gitu), lalu akan dikali dengan 10 decimal
        // karena amount akan berjumlah 1e18 (dalam wei), maka price harus diconvert menjadi 1e18 juga
        // supaya memudahkan perhitungan
    }

    // done
    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        (totalDSCMinted, collateralValueInUSD) = _getAccountInformation(user);
    }
    //
}
