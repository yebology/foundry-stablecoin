// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // ini itu buat cegah supaya function e gabisa dihack
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// DSC harus selalu overcollateralized
// DSCEngine ini yang kontrol StableCoin
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__TokenAddressesAndPriceFeedMustBeSameLength();
    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    DecentralizedStableCoin private immutable i_dsc;

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
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    // kalo rasio likuidasinya dibawah 1, mereka bisa dapat likuidasi
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDSCMinted,
            uint256 collateralValueInUSD
        ) = _getAccountInformation(user);
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
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        // apakah mereka punya cukup collateral?
        // kalo ga, revert
    }

    function getAccountCollatealValue(address user) public view returns (uint256) {
        // loop di tiap collateral token, cari berapa besar user deposit dan mappinglah buat dapetin USD value
    }
}
