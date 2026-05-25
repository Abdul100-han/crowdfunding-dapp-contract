// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AggregatorV3Interface} from
    "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockV3Aggregator
 * @author Crowdfunding DApp
 * @notice Minimal mock Chainlink price feed for Foundry tests.
 * @dev Stores a configurable answer and round metadata so tests can control ETH/USD pricing.
 */
contract MockV3Aggregator is AggregatorV3Interface {
    /// @notice Number of decimals used by the mock answer.
    uint8 private immutable i_decimals;

    /// @notice Human-readable feed description.
    string private s_description;

    /// @notice Feed version returned by the mock.
    uint256 private s_version;

    /// @notice Current round id used by the mock.
    uint80 private s_roundId;

    /// @notice Current answer returned by `latestRoundData`.
    int256 private s_answer;

    /// @notice Timestamp when the current round started.
    uint256 private s_startedAt;

    /// @notice Timestamp when the current answer was last updated.
    uint256 private s_updatedAt;

    /// @notice Round id in which the answer was computed.
    uint80 private s_answeredInRound;

    /**
     * @notice Initializes the mock price feed.
     * @param feedDecimals Number of decimals used by the mock answer.
     * @param initialAnswer Initial price answer to expose.
     */
    constructor(uint8 feedDecimals, int256 initialAnswer) {
        i_decimals = feedDecimals;
        s_description = "Mock V3 Aggregator";
        s_version = 1;
        _updateAnswer(initialAnswer);
    }

    /**
     * @notice Returns the answer decimals.
     * @return The number of decimals used by the feed.
     */
    function decimals() external view override returns (uint8) {
        return i_decimals;
    }

    /**
     * @notice Returns the feed description.
     * @return The feed description string.
     */
    function description() external view override returns (string memory) {
        return s_description;
    }

    /**
     * @notice Returns the feed version.
     * @return The mock version number.
     */
    function version() external view override returns (uint256) {
        return s_version;
    }

    /**
     * @notice Returns round data for a given round id.
     * @dev This mock only supports returning the latest round.
     * @param roundId The round id being queried.
     * @return returnedRoundId The stored round id.
     * @return answer The stored price answer.
     * @return startedAt The round start timestamp.
     * @return updatedAt The round update timestamp.
     * @return answeredInRound The round id in which the answer was computed.
     */
    function getRoundData(uint80 roundId)
        external
        view
        override
        returns (
            uint80 returnedRoundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        require(roundId == s_roundId, "unsupported round");
        return (s_roundId, s_answer, s_startedAt, s_updatedAt, s_answeredInRound);
    }

    /**
     * @notice Returns the latest round data.
     * @return roundId The stored round id.
     * @return answer The stored price answer.
     * @return startedAt The round start timestamp.
     * @return updatedAt The round update timestamp.
     * @return answeredInRound The round id in which the answer was computed.
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (s_roundId, s_answer, s_startedAt, s_updatedAt, s_answeredInRound);
    }

    /**
     * @notice Updates the latest answer and timestamps.
     * @param newAnswer The new price answer to expose.
     */
    function updateAnswer(int256 newAnswer) external {
        _updateAnswer(newAnswer);
    }

    /**
     * @notice Internal helper to roll the feed forward to a new round.
     * @param newAnswer The new price answer.
     */
    function _updateAnswer(int256 newAnswer) internal {
        s_roundId++;
        s_answer = newAnswer;
        s_startedAt = block.timestamp;
        s_updatedAt = block.timestamp;
        s_answeredInRound = s_roundId;
    }
}
