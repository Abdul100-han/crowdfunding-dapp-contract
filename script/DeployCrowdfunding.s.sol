// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {Crowdfunding} from "../src/Crowdfunding.sol";

/**
 * @title DeployCrowdfunding
 * @author Crowdfunding DApp
 * @notice Foundry deployment script for the Crowdfunding contract on Sepolia.
 */
contract DeployCrowdfunding is Script {
    /// @notice Minimum contribution threshold expressed in USD with 18 decimals.
    uint256 private constant MINIMUM_USD_CONTRIBUTION = 2e17;

    /// @notice Funding target expressed in USD with 18 decimals.
    uint256 private constant FUNDING_TARGET_USD = 2e18;

    /// @notice Campaign duration expressed in seconds for a 60-day campaign.
    uint256 private constant CAMPAIGN_DURATION = 60 days;

    /// @notice Chainlink Sepolia ETH/USD price feed.
    address private constant SEPOLIA_ETH_USD_PRICE_FEED =
            0x694AA1769357215DE4FAC081bf1f309aDC325306;
        // 0x694aa18559F431442F925085d7994A010305BA10;

    /**
     * @notice Broadcasts the deployment transaction and returns the deployed contract address.
     * @return deployedCrowdfundingAddress The address of the deployed Crowdfunding contract.
     */
    function run() external returns (address deployedCrowdfundingAddress) {
        vm.startBroadcast();

        Crowdfunding crowdfunding = new Crowdfunding(
            MINIMUM_USD_CONTRIBUTION,
            FUNDING_TARGET_USD,
            CAMPAIGN_DURATION,
            SEPOLIA_ETH_USD_PRICE_FEED
        );

        vm.stopBroadcast();

        deployedCrowdfundingAddress = address(crowdfunding);
    }
}
