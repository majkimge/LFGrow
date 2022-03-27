// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.10;

import {IFollowModule} from '../../../interfaces/IFollowModule.sol';
import {ILensHub} from '../../../interfaces/ILensHub.sol';
import {Errors} from '../../../libraries/Errors.sol';
import {FeeModuleBase} from '../FeeModuleBase.sol';
import {ModuleBase} from '../ModuleBase.sol';
import {FollowValidatorFollowModuleBase} from './FollowValidatorFollowModuleBase.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

/**
 * @notice A struct containing the necessary data to execute follow actions on a given profile.
 *
 * @param currency The currency associated with this profile.
 * @param amount The following cost associated with this profile.
 * @param recipient The recipient address associated with this profile.
 */
struct ProfileData {
    address currency;
    uint256 amount;
    address recipient;
}

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

contract PriceConsumerV3 {
    mapping(address => address) internal priceFeeds;

    constructor() {
        AggregatorV3Interface ethPriceFeed = AggregatorV3Interface(
            0xF9680D99D6C9589e2a93a78A04A279e509205945
        );
        AggregatorV3Interface btcPriceFeed = AggregatorV3Interface(
            0xc907E116054Ad103354f2D350FD2514433D57F6f
        );
        AggregatorV3Interface maticPriceFeed = AggregatorV3Interface(
            0xAB594600376Ec9fD91F8e885dADF0CE036862dE0
        );

        priceFeeds[
            0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619
        ] = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
        priceFeeds[
            0xc907E116054Ad103354f2D350FD2514433D57F6f
        ] = 0xc907E116054Ad103354f2D350FD2514433D57F6f;
        priceFeeds[
            0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
        ] = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
    }

    function getLatestPrice(address tokenAddress) public view returns (int256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[tokenAddress]);
        require(priceFeeds[tokenAddress] != address(0));
        (
            ,
            /*uint80 roundID*/
            int256 price, /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/
            ,
            ,

        ) = priceFeed.latestRoundData();
        return price;
    }
}

/**
 * @title FeeFollowModule
 * @author Lens Protocol
 *
 * @notice This is a simple Lens FollowModule implementation, inheriting from the IFollowModule interface, but with additional
 * variables that can be controlled by governance, such as the governance & treasury addresses as well as the treasury fee.
 */
contract FixedCurrencyFeeFollowModule is
    IFollowModule,
    FeeModuleBase,
    FollowValidatorFollowModuleBase
{
    using SafeERC20 for IERC20;

    mapping(uint256 => ProfileData) internal _dataByProfile;

    ISwapRouter public immutable swapRouter;
    PriceConsumerV3 public immutable priceConsumer = new PriceConsumerV3();

    constructor(
        address hub,
        address moduleGlobals,
        ISwapRouter _swapRouter
    ) FeeModuleBase(moduleGlobals) ModuleBase(hub) {
        swapRouter = _swapRouter;
    }

    /**
     * @notice This follow module levies a fee on follows.
     *
     * @param data The arbitrary data parameter, decoded into:
     *      address currency: The currency address, must be internally whitelisted.
     *      uint256 amount: The currency total amount to levy.
     *      address recipient: The custom recipient address to direct earnings to.
     *
     * @return An abi encoded bytes parameter, which is the same as the passed data parameter.
     */
    function initializeFollowModule(uint256 profileId, bytes calldata data)
        external
        override
        onlyHub
        returns (bytes memory)
    {
        (uint256 amount, address currency, address recipient) = abi.decode(
            data,
            (uint256, address, address)
        );
        if (!_currencyWhitelisted(currency) || recipient == address(0) || amount < BPS_MAX)
            revert Errors.InitParamsInvalid();

        _dataByProfile[profileId].amount = amount;
        _dataByProfile[profileId].currency = currency;
        _dataByProfile[profileId].recipient = recipient;
        return data;
    }

    struct FeedInfo {
        uint256 priceFrom;
        uint256 priceTo;
        uint256 treasuryAmount;
        uint256 adjustedAmount;
        uint256 tokenFromDecimals;
        uint256 tokenToDecimals;
        uint256 amount;
        address currency;
        address recipient;
        uint256 adjustedDesiredIn;
        uint256 adjustedDesiredInMax;
        uint256 treasuryDesiredIn;
        uint256 treasuryDesiredInMax;
    }

    /**
     * @dev Processes a follow by:
     *  1. Charging a fee
     */
    function processFollow(
        address follower,
        uint256 profileId,
        bytes calldata data
    ) external override onlyHub {
        FeedInfo memory feedInfo;
        feedInfo.amount = _dataByProfile[profileId].amount;
        feedInfo.currency = _dataByProfile[profileId].currency;
        feedInfo.recipient = _dataByProfile[profileId].recipient;
        //_validateDataIsExpected(data, currency, amount);
        (address decodedCurrency, uint256 decodedAmount) = abi.decode(data, (address, uint256));
        (address treasury, uint16 treasuryFee) = _treasuryData();

        feedInfo.priceFrom = uint256(priceConsumer.getLatestPrice(decodedCurrency));
        feedInfo.priceTo = uint256(priceConsumer.getLatestPrice(feedInfo.currency));
        feedInfo.treasuryAmount = (feedInfo.amount * treasuryFee) / BPS_MAX;
        feedInfo.adjustedAmount = feedInfo.amount - feedInfo.treasuryAmount;
        feedInfo.tokenFromDecimals = ERC20(decodedCurrency).decimals();
        feedInfo.tokenToDecimals = ERC20(feedInfo.currency).decimals();
        feedInfo.adjustedDesiredIn =
            (feedInfo.adjustedAmount * feedInfo.priceTo * feedInfo.tokenFromDecimals) /
            (feedInfo.tokenToDecimals * feedInfo.priceFrom);

        feedInfo.adjustedDesiredInMax =
            feedInfo.adjustedDesiredIn +
            feedInfo.adjustedDesiredIn /
            50;

        feedInfo.treasuryDesiredIn =
            (feedInfo.treasuryAmount * feedInfo.priceTo * feedInfo.tokenFromDecimals) /
            (feedInfo.tokenToDecimals * feedInfo.priceFrom);
        feedInfo.treasuryDesiredInMax =
            feedInfo.treasuryDesiredIn +
            feedInfo.treasuryDesiredIn /
            50;

        exchangeAndSendToRecipient(
            follower,
            feedInfo.recipient,
            treasury,
            decodedCurrency,
            feedInfo.currency,
            feedInfo.treasuryDesiredInMax,
            feedInfo.adjustedDesiredInMax,
            feedInfo.treasuryAmount,
            feedInfo.adjustedAmount
        );
    }

    function exchangeAndSendToRecipient(
        address follower,
        address recipient,
        address treasury,
        address currencyFrom,
        address currencyTo,
        uint256 treasuryAmountIn,
        uint256 adjustedAmountIn,
        uint256 treasuryAmountOut,
        uint256 adjustedAmountOut
    ) internal {
        if (currencyFrom == currencyTo) {
            IERC20(currencyFrom).safeTransferFrom(follower, recipient, adjustedAmountIn);
            IERC20(currencyFrom).safeTransferFrom(follower, treasury, treasuryAmountIn);
        } else {
            // msg.sender must approve this contract
            uint256 amountInMax = treasuryAmountIn + adjustedAmountIn;
            // Transfer the specified amount of DAI to this contract.
            TransferHelper.safeTransferFrom(currencyFrom, msg.sender, address(this), amountInMax);

            // Approve the router to spend DAI.
            TransferHelper.safeApprove(currencyFrom, address(swapRouter), amountInMax);

            // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
            // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
            ISwapRouter.ExactOutputSingleParams memory paramsTreasury = ISwapRouter
                .ExactOutputSingleParams({
                    tokenIn: currencyFrom,
                    tokenOut: currencyTo,
                    fee: 3000,
                    recipient: treasury,
                    deadline: block.timestamp,
                    amountOut: treasuryAmountOut,
                    amountInMaximum: treasuryAmountIn,
                    sqrtPriceLimitX96: 0
                });

            // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
            uint256 amountIn = swapRouter.exactOutputSingle(paramsTreasury);

            ISwapRouter.ExactOutputSingleParams memory paramsRecipient = ISwapRouter
                .ExactOutputSingleParams({
                    tokenIn: currencyFrom,
                    tokenOut: currencyTo,
                    fee: 3000,
                    recipient: recipient,
                    deadline: block.timestamp,
                    amountOut: adjustedAmountOut,
                    amountInMaximum: adjustedAmountIn,
                    sqrtPriceLimitX96: 0
                });

            // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
            amountIn = amountIn + swapRouter.exactOutputSingle(paramsRecipient);

            // For exact output swaps, the amountInMaximum may not have all been spent.
            // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
            if (amountIn < amountInMax) {
                TransferHelper.safeApprove(currencyFrom, address(swapRouter), 0);
                TransferHelper.safeTransfer(currencyFrom, msg.sender, amountInMax - amountIn);
            }
        }
    }

    /**
     * @dev We don't need to execute any additional logic on transfers in this follow module.
     */
    function followModuleTransferHook(
        uint256 profileId,
        address from,
        address to,
        uint256 followNFTTokenId
    ) external override {}

    /**
     * @notice Returns the profile data for a given profile, or an empty struct if that profile was not initialized
     * with this module.
     *
     * @param profileId The token ID of the profile to query.
     *
     * @return The ProfileData struct mapped to that profile.
     */
    function getProfileData(uint256 profileId) external view returns (ProfileData memory) {
        return _dataByProfile[profileId];
    }
}
