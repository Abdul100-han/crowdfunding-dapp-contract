// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Crowdfunding} from "../src/Crowdfunding.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

/**
 * @title RefundReentrancyAttacker
 * @notice Test helper that attempts to reenter `getRefund()` from its receive hook.
 */
contract RefundReentrancyAttacker {
    /// @notice Target crowdfunding contract under test.
    Crowdfunding private immutable i_crowdfunding;

    /// @notice Tracks whether the helper already attempted reentrancy.
    bool private s_attemptedReentry;

    /**
     * @notice Stores the crowdfunding target address.
     * @param crowdfundingAddress Address of the deployed crowdfunding contract.
     */
    constructor(address crowdfundingAddress) {
        i_crowdfunding = Crowdfunding(crowdfundingAddress);
    }

    /**
     * @notice Funds the target campaign from this contract.
     */
    function fundCampaign() external payable {
        i_crowdfunding.fund{value: msg.value}();
    }

    /**
     * @notice Initiates a refund attempt.
     */
    function attackRefund() external {
        i_crowdfunding.getRefund();
    }

    /**
     * @notice Returns whether a reentrant refund call was attempted.
     * @return True if reentrancy was attempted.
     */
    function attemptedReentry() external view returns (bool) {
        return s_attemptedReentry;
    }

    /**
     * @notice Attempts a second refund during the first refund transfer.
     * @dev The target should reject the second call because the balance is zeroed first.
     */
    receive() external payable {
        if (!s_attemptedReentry) {
            s_attemptedReentry = true;
            try i_crowdfunding.getRefund() {} catch {}
        }
    }
}

/**
 * @title CrowdfundingTest
 * @notice Unit tests for the `Crowdfunding` contract.
 */
contract CrowdfundingTest is Test {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant INITIAL_ETH_PRICE = 2_000e8;

    uint256 private constant MINIMUM_USD = 1e18;
    uint256 private constant GOAL_USD = 1_000e18;
    uint256 private constant DURATION = 1 days;

    uint256 private constant BELOW_MINIMUM_CONTRIBUTION = 0.0004 ether;
    uint256 private constant STANDARD_CONTRIBUTION = 0.1 ether;
    uint256 private constant GOAL_MEETING_CONTRIBUTION = 0.5 ether;
    uint256 private constant EXTRA_CONTRIBUTION = 0.1 ether;

    address private constant USER = address(0xA11CE);
    address private constant USER_TWO = address(0xB0B);
    address private constant NON_OWNER = address(0xBAD);

    MockV3Aggregator private mockPriceFeed;
    Crowdfunding private crowdfunding;

    function setUp() external {
        mockPriceFeed = new MockV3Aggregator(FEED_DECIMALS, INITIAL_ETH_PRICE);
        crowdfunding =
            new Crowdfunding(MINIMUM_USD, GOAL_USD, DURATION, address(mockPriceFeed));

        vm.deal(address(this), 10 ether);
        vm.deal(USER, 10 ether);
        vm.deal(USER_TWO, 10 ether);
        vm.deal(NON_OWNER, 10 ether);
    }

    receive() external payable {}

    function testFundRevertsWhenContributionIsBelowMinimumUsd() external {
        vm.prank(USER);
        vm.expectRevert(Crowdfunding.Crowdfunding__BelowMinimumUsd.selector);
        crowdfunding.fund{value: BELOW_MINIMUM_CONTRIBUTION}();
    }

    function testFundRecordsUniqueFunderAndUpdatesAccounting() external {
        vm.startPrank(USER);
        crowdfunding.fund{value: STANDARD_CONTRIBUTION}();
        crowdfunding.fund{value: STANDARD_CONTRIBUTION}();
        vm.stopPrank();

        assertEq(crowdfunding.getFunderCount(), 1);
        assertEq(crowdfunding.getFunderAtIndex(0), USER);
        assertEq(crowdfunding.getAddressToAmountFunded(USER), STANDARD_CONTRIBUTION * 2);
        assertEq(crowdfunding.getTotalUsdRaised(), 400e18);
    }

    function testSetMinimumUsdContributionUpdatesThreshold() external {
        crowdfunding.setMinimumUsdContribution(5e18);

        assertEq(crowdfunding.getMinimumUsdContribution(), 5e18);
    }

    function testSetMinimumUsdContributionRevertsWhenCallerIsNotOwner() external {
        vm.prank(NON_OWNER);
        vm.expectRevert(Crowdfunding.Crowdfunding__NotOwner.selector);
        crowdfunding.setMinimumUsdContribution(5e18);
    }

    function testSetMinimumUsdContributionRevertsWhenZero() external {
        vm.expectRevert(Crowdfunding.Crowdfunding__InvalidMinimumUsd.selector);
        crowdfunding.setMinimumUsdContribution(0);
    }

    function testWithdrawRevertsWhenCallerIsNotOwner() external {
        vm.prank(NON_OWNER);
        vm.expectRevert(Crowdfunding.Crowdfunding__NotOwner.selector);
        crowdfunding.withdraw();
    }

    function testWithdrawRevertsWhenDeadlineHasNotPassed() external {
        vm.prank(USER);
        crowdfunding.fund{value: GOAL_MEETING_CONTRIBUTION}();

        vm.expectRevert(Crowdfunding.Crowdfunding__DeadlineNotReached.selector);
        crowdfunding.withdraw();
    }

    function testWithdrawRevertsWhenTargetIsNotMetAfterDeadline() external {
        vm.prank(USER);
        crowdfunding.fund{value: STANDARD_CONTRIBUTION}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.expectRevert(Crowdfunding.Crowdfunding__TargetNotMet.selector);
        crowdfunding.withdraw();
    }

    function testWithdrawTransfersFullBalanceToOwnerWhenCampaignSucceeds() external {
        vm.prank(USER);
        crowdfunding.fund{value: GOAL_MEETING_CONTRIBUTION}();

        vm.prank(USER_TWO);
        crowdfunding.fund{value: EXTRA_CONTRIBUTION}();

        uint256 ownerStartingBalance = address(this).balance;
        uint256 contractStartingBalance = address(crowdfunding).balance;

        vm.warp(block.timestamp + DURATION + 1);

        crowdfunding.withdraw();

        assertEq(address(crowdfunding).balance, 0);
        assertEq(address(this).balance, ownerStartingBalance + contractStartingBalance);
    }

    function testGetRefundReturnsExactContributionAndClearsState() external {
        vm.prank(USER);
        crowdfunding.fund{value: STANDARD_CONTRIBUTION}();

        uint256 userBalanceBeforeRefund = USER.balance;

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(USER);
        crowdfunding.getRefund();

        assertEq(USER.balance, userBalanceBeforeRefund + STANDARD_CONTRIBUTION);
        assertEq(crowdfunding.getAddressToAmountFunded(USER), 0);
        assertEq(address(crowdfunding).balance, 0);

        vm.prank(USER);
        vm.expectRevert(Crowdfunding.Crowdfunding__NothingToRefund.selector);
        crowdfunding.getRefund();
    }

    function testGetRefundBlocksReentrancyByZeroingStateBeforeTransfer() external {
        RefundReentrancyAttacker attacker = new RefundReentrancyAttacker(address(crowdfunding));

        attacker.fundCampaign{value: STANDARD_CONTRIBUTION}();

        vm.warp(block.timestamp + DURATION + 1);

        attacker.attackRefund();

        assertTrue(attacker.attemptedReentry());
        assertEq(crowdfunding.getAddressToAmountFunded(address(attacker)), 0);
        assertEq(address(attacker).balance, STANDARD_CONTRIBUTION);
        assertEq(address(crowdfunding).balance, 0);
    }
}
