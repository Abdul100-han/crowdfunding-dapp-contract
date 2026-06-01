// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Crowdfunding
 * @author Crowdfunding DApp
 * @notice Accepts ETH contributions toward a USD-denominated goal using a Chainlink ETH/USD price feed.
 * @dev Successful campaigns allow the owner to withdraw after the deadline; failed campaigns enable per-funder refunds.
 */
contract Crowdfunding {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

  /// @notice Thrown when a caller is not the contract owner.
  error Crowdfunding__NotOwner();

  /// @notice Thrown when the USD funding goal has not been reached.
  error Crowdfunding__TargetNotMet();

  /// @notice Thrown when the campaign deadline has not yet passed.
  error Crowdfunding__DeadlineNotReached();

  /// @notice Thrown when attempting to fund after the campaign deadline.
  error Crowdfunding__DeadlineReached();

  /// @notice Thrown when the sent ETH is below the minimum USD contribution threshold.
  error Crowdfunding__BelowMinimumUsd();

  /// @notice Thrown when an ETH transfer to a recipient fails.
  error Crowdfunding__TransferFailed();

  /// @notice Thrown when the Chainlink price feed returns a non-positive price.
  error Crowdfunding__InvalidPrice();

  /// @notice Thrown when the Chainlink price feed data is stale.
  error Crowdfunding__StalePriceFeed();

  /// @notice Thrown when a funder has no recorded contribution to refund.
  error Crowdfunding__NothingToRefund();

  /// @notice Thrown when refunds are requested but the funding goal was already met.
  error Crowdfunding__TargetAlreadyMet();

  /// @notice Thrown when no ETH is sent with a fund call.
  error Crowdfunding__ZeroContribution();

  /// @notice Thrown when constructor arguments are invalid.
  error Crowdfunding__InvalidConstructorArgs();

  /// @notice Thrown when setting a zero minimum USD contribution.
  error Crowdfunding__InvalidMinimumUsd();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when an address contributes ETH to the campaign.
  /// @param funder The address that sent ETH.
  /// @param amount The amount of ETH contributed in wei.
  event Funded(address indexed funder, uint256 amount);

  /// @notice Emitted when the owner withdraws the contract balance after a successful campaign.
  /// @param owner The owner address that received the funds.
  /// @param amount The amount of ETH withdrawn in wei.
  event Withdrawn(address indexed owner, uint256 amount);

  /// @notice Emitted when a funder receives a refund after a failed campaign.
  /// @param funder The address that received the refund.
  /// @param amount The amount of ETH refunded in wei.
  event Refunded(address indexed funder, uint256 amount);

  /// @notice Emitted when the owner updates the minimum USD contribution.
  /// @param newMinimumUsd The new minimum in USD with 18 decimals.
  event MinimumUsdContributionUpdated(uint256 newMinimumUsd);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

  /// @notice The address that created the campaign and may withdraw on success.
  address private immutable i_owner;

  /// @notice Minimum allowed contribution expressed in USD with 18 decimals.
  uint256 private s_minimumUsdContribution;

  /// @notice Funding goal expressed in USD with 18 decimals.
  uint256 private immutable i_fundingGoalUsd;

  /// @notice Unix timestamp after which funding stops and settlement is allowed.
  uint256 private immutable i_deadline;

  /// @notice Chainlink ETH/USD price feed used to value incoming contributions.
  AggregatorV3Interface private immutable i_priceFeed;

  /// @notice Number of decimals returned by the Chainlink price feed answer.
  uint8 private immutable i_priceFeedDecimals;

  /// @notice Cumulative USD value of all contributions, stored with 18 decimals.
  uint256 private s_totalUsdRaised;

  /// @notice Tracks total ETH (in wei) contributed by each address.
  mapping(address => uint256) private s_addressToAmountFunded;

  /// @notice List of unique addresses that have funded the campaign at least once.
  address[] private s_funders;

  /// @notice Maximum age (in seconds) allowed for the latest Chainlink round update.
  uint256 private constant STALE_PRICE_THRESHOLD = 3 hours;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploys a new crowdfunding campaign.
   * @param minimumUsdContribution Minimum contribution in USD with 18 decimals (e.g. `1e18` for $1).
   * @param fundingGoalUsd Target raise amount in USD with 18 decimals.
   * @param durationInSeconds Campaign length in seconds from deployment time.
   * @param priceFeed Address of the Chainlink ETH/USD AggregatorV3 price feed.
   */
  constructor(
    uint256 minimumUsdContribution,
    uint256 fundingGoalUsd,
    uint256 durationInSeconds,
    address priceFeed
  ) {
    if (
      minimumUsdContribution == 0 || fundingGoalUsd == 0 || durationInSeconds == 0
        || priceFeed == address(0)
    ) {
      revert Crowdfunding__InvalidConstructorArgs();
    }

    i_owner = msg.sender;
    s_minimumUsdContribution = minimumUsdContribution;
    i_fundingGoalUsd = fundingGoalUsd;
    i_deadline = block.timestamp + durationInSeconds;
    i_priceFeed = AggregatorV3Interface(priceFeed);
    i_priceFeedDecimals = i_priceFeed.decimals();
  }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Contribute ETH to the campaign while it is active.
   * @dev Reverts if the deadline has passed, no ETH is sent, or the USD value is below the minimum.
   *      Records the contributor in `s_addressToAmountFunded` and appends unique funders to `s_funders`.
   */
  function fund() external payable {
    if (block.timestamp > i_deadline) {
      revert Crowdfunding__DeadlineReached();
    }
    if (msg.value == 0) {
      revert Crowdfunding__ZeroContribution();
    }

    uint256 usdValue = _getEthUsdValue(msg.value);
    if (usdValue < s_minimumUsdContribution) {
      revert Crowdfunding__BelowMinimumUsd();
    }

    if (s_addressToAmountFunded[msg.sender] == 0) {
      s_funders.push(msg.sender);
    }

    s_addressToAmountFunded[msg.sender] += msg.value;
    s_totalUsdRaised += usdValue;

    emit Funded(msg.sender, msg.value);
  }

  /**
   * @notice Allows the owner to withdraw the full contract balance after a successful campaign.
   * @dev Callable only after the deadline and only when `s_totalUsdRaised` meets or exceeds the goal.
   */
  function withdraw() external onlyOwner {
    if (block.timestamp <= i_deadline) {
      revert Crowdfunding__DeadlineNotReached();
    }
    if (s_totalUsdRaised < i_fundingGoalUsd) {
      revert Crowdfunding__TargetNotMet();
    }

    uint256 contractBalance = address(this).balance;

    (bool success,) = payable(i_owner).call{value: contractBalance}("");
    if (!success) {
      revert Crowdfunding__TransferFailed();
    }

    emit Withdrawn(i_owner, contractBalance);
  }

  /**
   * @notice Returns a funder's exact deposited ETH when the campaign fails to reach its goal.
   * @dev Callable only after the deadline and only while the USD goal was not met.
   */
  function getRefund() external {
    if (block.timestamp <= i_deadline) {
      revert Crowdfunding__DeadlineNotReached();
    }
    if (s_totalUsdRaised >= i_fundingGoalUsd) {
      revert Crowdfunding__TargetAlreadyMet();
    }

    uint256 amountToRefund = s_addressToAmountFunded[msg.sender];
    if (amountToRefund == 0) {
      revert Crowdfunding__NothingToRefund();
    }

    s_addressToAmountFunded[msg.sender] = 0;

    (bool success,) = payable(msg.sender).call{value: amountToRefund}("");
    if (!success) {
      revert Crowdfunding__TransferFailed();
    }

    emit Refunded(msg.sender, amountToRefund);
  }

  /**
   * @notice Updates the minimum USD contribution threshold.
   * @dev Callable only by the owner. Reverts if `_newMinUsd` is zero.
   * @param _newMinUsd New minimum contribution in USD with 18 decimals (e.g. `1e18` for $1).
   */
  function setMinimumUsdContribution(uint256 _newMinUsd) external onlyOwner {
    if (_newMinUsd == 0) {
      revert Crowdfunding__InvalidMinimumUsd();
    }

    s_minimumUsdContribution = _newMinUsd;
    emit MinimumUsdContributionUpdated(_newMinUsd);
  }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the contract owner address.
   * @return The campaign owner.
   */
  function getOwner() external view returns (address) {
    return i_owner;
  }

  /**
   * @notice Returns the minimum USD contribution with 18 decimals.
   * @return The minimum contribution threshold.
   */
  function getMinimumUsdContribution() external view returns (uint256) {
    return s_minimumUsdContribution;
  }

  /**
   * @notice Returns the USD funding goal with 18 decimals.
   * @return The funding target.
   */
  function getFundingGoalUsd() external view returns (uint256) {
    return i_fundingGoalUsd;
  }

  /**
   * @notice Returns the campaign deadline as a Unix timestamp.
   * @return The deadline timestamp.
   */
  function getDeadline() external view returns (uint256) {
    return i_deadline;
  }

  /**
   * @notice Returns the configured Chainlink price feed address.
   * @return The price feed contract address.
   */
  function getPriceFeed() external view returns (address) {
    return address(i_priceFeed);
  }

  /**
   * @notice Returns cumulative USD raised at historical contribution prices (18 decimals).
   * @return Total USD raised.
   */
  function getTotalUsdRaised() external view returns (uint256) {
    return s_totalUsdRaised;
  }

  /**
   * @notice Returns the ETH amount a given address has contributed.
   * @param funder The address to query.
   * @return The total wei contributed by `funder`.
   */
  function getAddressToAmountFunded(address funder) external view returns (uint256) {
    return s_addressToAmountFunded[funder];
  }

  /**
   * @notice Returns the number of unique funders.
   * @return The length of the funders array.
   */
  function getFunderCount() external view returns (uint256) {
    return s_funders.length;
  }

  /**
   * @notice Returns a funder address by index.
   * @param index Position in the `s_funders` array.
   * @return The funder address at `index`.
   */
  function getFunderAtIndex(uint256 index) external view returns (address) {
    return s_funders[index];
  }

  /**
   * @notice Returns the USD value of a given ETH amount using the latest Chainlink price.
   * @param ethAmountWei Amount of ETH in wei to convert.
   * @return usdValue The equivalent USD amount with 18 decimals.
   */
  function getEthUsdValue(uint256 ethAmountWei) external view returns (uint256 usdValue) {
    return _getEthUsdValue(ethAmountWei);
  }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Fetches and validates the latest Chainlink price, then converts ETH to USD (18 decimals).
   * @param ethAmountWei Amount of ETH in wei.
   * @return usdValue USD value with 18 decimals.
   */
  function _getEthUsdValue(uint256 ethAmountWei) internal view returns (uint256 usdValue) {
    (, int256 ethUsdPrice,, uint256 updatedAt,) = i_priceFeed.latestRoundData();

    if (ethUsdPrice <= 0) {
      revert Crowdfunding__InvalidPrice();
    }
    if (updatedAt == 0 || block.timestamp - updatedAt > STALE_PRICE_THRESHOLD) {
      revert Crowdfunding__StalePriceFeed();
    }

    uint256 price = uint256(ethUsdPrice);
    uint256 feedScale = 10 ** uint256(i_priceFeedDecimals);

    usdValue = (ethAmountWei * price) / feedScale;
  }

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Restricts function access to the campaign owner.
   */
  modifier onlyOwner() {
    if (msg.sender != i_owner) {
      revert Crowdfunding__NotOwner();
    }
    _;
  }
}
