// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/EnumerableMap.sol";
import "./DiceNFT.sol";
import "./Governable.sol";

contract DiceGame is Governable {
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    event GameCreated(address indexed creator, uint256 indexed gameId);
    event GameRolled(uint256 indexed gameId, uint256 number);
    event GameSucceeded(uint256 indexed gameId);
    event RollTimeAdded(uint256 indexed gameId, uint256 rollTimeLeft);

    struct Pool {
        uint256 id;
        address payable creator;
        uint256[] dices;
        uint256 rewardPoints;
        uint256 endTime;
        uint256 currentRound;
        uint256 rollTimesLeft;
        bool success;
    }

    struct PlayerPoints {
        address player;
        uint256 rewardPoints;
    }

    // configurations
    uint256 private maxDiceCountPerGame;
    uint256 private initialGameTimes;
    uint256 private maxGameTimes;
    uint256 private gameDurationInSecond;
    uint256 private initialRewardPoints;
    uint256 private initialRollTimes;
    uint256 private gameCreationInterval;
    uint256 private rewardPointsPerRoll;
    uint256 private minRewardPoints;

    DiceNFT private diceNft;

    Pool[] private pools;
    mapping(address => uint256[]) private playerPools;
    mapping(address => uint256) private playerRewardPoints;
    mapping(uint256 => uint256) private diceRolledTimes;

    mapping(address => uint256) private gameTimes;
    mapping(address => uint256) private newGameCountDownStartAt;

    EnumerableMap.UintToAddressMap private sortedTotalTop50; 

    address private rewardAdmin;
    uint256 private rewardPeriodStartTime;
    mapping(address => uint256) private playerPeriodicRewardPoints;
    mapping(address => uint256) private playerPeriodicLastUpdateTime;
    EnumerableMap.UintToAddressMap private sortedPeriodicTop50;

    function initialize(address _governor) public override initializer {
        super.initialize(_governor);
        maxDiceCountPerGame = 3;
        initialGameTimes = 3;
        maxGameTimes = 3;
        gameDurationInSecond = 86400; // one day
        initialRewardPoints = 10000;
        initialRollTimes = 6;
        gameCreationInterval = 28800; // 8 hours
        rewardPointsPerRoll = 100;
        minRewardPoints = 0;
        rewardPeriodStartTime = block.timestamp;
    }

    function setMaxDiceCountPerGame(uint256 _maxDiceCountPerGame) external governance {
        maxDiceCountPerGame = _maxDiceCountPerGame;
    }

    function setInitialGameTimes(uint256 _initialGameTimes) external governance {
        initialGameTimes = _initialGameTimes;
    }

    function setMaxGameTimes(uint256 _maxGameTimes) external governance {
        maxGameTimes = _maxGameTimes;
    }

    function setGameDurationInSecond(uint256 _gameDurationInSecond) external governance {
        gameDurationInSecond = _gameDurationInSecond;
    }

    function setInitialRewardPoints(uint256 _initialRewardPoints) external governance {
        initialRewardPoints = _initialRewardPoints;
    }

    function setInitialRollTimes(uint256 _initialRollTimes) external governance {
        initialRollTimes = _initialRollTimes;
    }

    function setGameCreationInterval(uint256 _gameCreationInterval) external governance {
        gameCreationInterval = _gameCreationInterval;
    }

    function setRewardPointsPerRoll(uint256 _rewardPointsPerRoll) external governance {
        rewardPointsPerRoll = _rewardPointsPerRoll;
    }

    function setMinRewardPoints(uint256 _minRewardPoints) external governance {
        minRewardPoints = _minRewardPoints;
    }

    function setDiceNft(address _diceNft) external governance {
        diceNft = DiceNFT(_diceNft);
    }

    function setRewardAdmin(address _rewardAdmin) external governance {
        rewardAdmin = _rewardAdmin;
    }

    function getMaxDiceCountPerGame() external view returns (uint256) {
        return maxDiceCountPerGame;
    }

    function getInitialGameTimes() external view returns (uint256) {
        return initialGameTimes;
    }

    function getMaxGameTimes() external view returns (uint256) {
        return maxGameTimes;
    }

    function getGameDurationInSecond() external view returns (uint256) {
        return gameDurationInSecond;
    }

    function getInitialRewardPoints() external view returns (uint256) {
        return initialRewardPoints;
    }

    function getInitialRollTimes() external view returns (uint256) {
        return initialRollTimes;
    }

    function getGameCreationInterval() external view returns (uint256) {
        return gameCreationInterval;
    }

    function getRewardPointsPerRoll() external view returns (uint256) {
        return rewardPointsPerRoll;
    }

    function getMinRewardPoints() external view returns (uint256) {
        return minRewardPoints;
    }

    function getRewardPeriodStartTime() external view returns (uint256) {
        return rewardPeriodStartTime;
    }

    function getGameTimesAndCountDownStartAt(address player) external view returns (uint256, uint256) {
        if (gameTimes[player] == 0 && newGameCountDownStartAt[player] == 0) {
            return (initialGameTimes, 0);
        } else {
            return (gameTimes[player], newGameCountDownStartAt[player]);
        }
    }

    function getGame(uint256 gameId) external view returns (Pool memory) {
        require(_validGameId(gameId), "invalid game id");
        return pools[gameId];
    }

    function getGameIds(address player) external view returns (uint256[] memory) {
        return playerPools[player];
    }

    function getTotalRewardPoint(address player) external view returns (uint256) {
        return playerRewardPoints[player];
    }

    function getTotalTop50() external view returns (PlayerPoints[] memory) {
        PlayerPoints[] memory top50 = new PlayerPoints[](sortedTotalTop50.length());
        for (uint i = 1; i <= sortedTotalTop50.length(); i++) {
            PlayerPoints memory player;
            player.player = sortedTotalTop50.get(i);
            player.rewardPoints = playerRewardPoints[player.player];
            top50[i - 1] = player;
        }
        return top50;
    }

    function getPeriodicRewardPoint(address player) external view returns (uint256) {
        return playerPeriodicLastUpdateTime[player] <= rewardPeriodStartTime ? 0 : playerPeriodicRewardPoints[player];
    }

    function getPeriodicTop50() external view returns (PlayerPoints[] memory) {
        PlayerPoints[] memory top50 = new PlayerPoints[](sortedPeriodicTop50.length());
        for (uint i = 1; i <= sortedPeriodicTop50.length(); i++) {
            PlayerPoints memory player;
            player.player = sortedPeriodicTop50.get(i);
            player.rewardPoints = playerPeriodicRewardPoints[player.player];
            top50[i - 1] = player;
        }
        return top50;
    }

    function newGame(uint256[] memory dices) external returns (uint256) {
        address payable creator = msg.sender;

        _updatePlayerGameTimes(creator);
        require(gameTimes[creator] > 0, "no times left");
        if (gameTimes[creator] == maxGameTimes || newGameCountDownStartAt[creator] == 0) {
            newGameCountDownStartAt[creator] = block.timestamp;
        }
        gameTimes[creator] = gameTimes[creator] - 1;
        
        for (uint i = 0; i < dices.length && i < maxDiceCountPerGame; i++) {
            require(creator == diceNft.ownerOf(dices[i]), "not owner of dice");
        }

        uint256 id = pools.length;
        Pool memory pool;
        pool.id = id;
        pool.creator = creator;
        uint256 diceCount = dices.length <= maxDiceCountPerGame ? dices.length : maxDiceCountPerGame;
        pool.dices = new uint256[](diceCount);
        for (uint i = 0; i < diceCount; i++) {
            pool.dices[i] = dices[i];
        }
        pool.rewardPoints = initialRewardPoints;
        pool.endTime = block.timestamp + gameDurationInSecond;
        pool.currentRound = 1;
        pool.rollTimesLeft = initialRollTimes;
        pool.success = false;

        pools.push(pool);
        playerPools[creator].push(id);

        emit GameCreated(creator, id);

        return id;
    }

    function roll(uint256 gameId, uint256 diceId) external playable(gameId) returns (uint256) {
        Pool storage pool = pools[gameId];

        require(pool.creator == msg.sender, "not game creator");
        require(pool.rollTimesLeft > 0, "no roll times left");
        require(_isGameDice(gameId, diceId), "dice cannot be used for this game");
        require(msg.sender == diceNft.ownerOf(diceId), "not owner of dice");

        pool.rollTimesLeft -= 1;
        diceRolledTimes[diceId] += 1;
        uint256 rollResult = diceNft.roll(diceId, pool.currentRound);
        if (rollResult == pool.currentRound) { // success
            if (pool.currentRound != 6) { // not last round
                pool.currentRound += 1;
            } else {
                pool.success = true;
                playerRewardPoints[pool.creator] += pool.rewardPoints;
                _onRewardPointsUpdated(pool.creator, playerRewardPoints[pool.creator], pool.rewardPoints);
            }
        }

        emit GameRolled(gameId, rollResult);
        if (pool.success) {
            emit GameSucceeded(gameId);
        }
        return rollResult;
    }

    function addRollTimes(uint256 gameId, uint256 times) external playable(gameId) {
        Pool storage pool = pools[gameId];

        require(pool.creator == msg.sender, "not game creator");
        require(pool.rewardPoints >= rewardPointsPerRoll * times + minRewardPoints, "no enough points");

        pool.rewardPoints -= rewardPointsPerRoll * times;
        pool.rollTimesLeft += times;

        emit RollTimeAdded(gameId, pool.rollTimesLeft);
    }

    function newRewardPeriod() external {
        require(msg.sender == rewardAdmin || msg.sender == governor, "not reward admin or governor");
        rewardPeriodStartTime = block.timestamp;

        for (uint i = sortedPeriodicTop50.length(); i >0; i--) {
            sortedPeriodicTop50.remove(i);
        }
    }

    function _onRewardPointsUpdated(address player, uint256 newRewardPoints, uint256 addRewardPoints) internal {
        _updateTotalTop50(player, newRewardPoints);
        _updatePeriodicTop50(player, addRewardPoints);
    }

    function _updateTotalTop50(address player, uint256 newRewardPoints) internal {
        uint256 count = sortedTotalTop50.length();
        uint256 oldIndex;
        uint256 newIndex;
        for (uint i = count; i > 0; i--) {
            if (sortedTotalTop50.get(i) == player) {
                oldIndex = i;
                continue;
            }

            if (playerRewardPoints[sortedTotalTop50.get(i)] >= newRewardPoints) {
                newIndex = i + 1;
                break;
            }
        }
        if (newIndex == 0) {
            newIndex = 1;
        }
        if (newIndex <= 50) {
            uint256 start = oldIndex > 0 ? oldIndex : (count == 50 ? 50 : count + 1);
            for (uint i = start; i > newIndex; i--) {
                sortedTotalTop50.set(i, sortedTotalTop50.get(i - 1));
            }
            sortedTotalTop50.set(newIndex, player);
        }
    }

    function _updatePeriodicTop50(address player, uint256 addedRewardPoints) internal {
        if (playerPeriodicLastUpdateTime[player] > rewardPeriodStartTime) {
            playerPeriodicRewardPoints[player] += addedRewardPoints;
        } else {
            playerPeriodicRewardPoints[player] = addedRewardPoints;
        }
        playerPeriodicLastUpdateTime[player] = block.timestamp == rewardPeriodStartTime ? block.timestamp + 1 : block.timestamp;

        // update top50
        uint256 newRewardPoints = playerPeriodicRewardPoints[player];
        uint256 count = sortedPeriodicTop50.length();
        uint256 oldIndex;
        uint256 newIndex;
        for (uint i = count; i > 0; i--) {
            if (sortedPeriodicTop50.get(i) == player) {
                oldIndex = i;
                continue;
            }
            if (playerPeriodicRewardPoints[sortedPeriodicTop50.get(i)] >= newRewardPoints) {
                newIndex = i + 1;
                break;
            }
        }
        if (newIndex == 0) {
            newIndex = 1;
        }
        if (newIndex <= 50) {
            uint256 start = oldIndex > 0 ? oldIndex : (count == 50 ? 50 : count + 1);
            for (uint i = start; i > newIndex; i--) {
                sortedPeriodicTop50.set(i, sortedPeriodicTop50.get(i - 1));
            }
            sortedPeriodicTop50.set(newIndex, player);
        }
    }

    function _updatePlayerGameTimes(address player) internal {
        if (gameTimes[player] == maxGameTimes) {
            return;
        }

        // set initial times for player
        if (newGameCountDownStartAt[player] == 0 && gameTimes[player] == 0) {
            gameTimes[player] = initialGameTimes;
            return;
        }

        uint256 timePassed = block.timestamp - newGameCountDownStartAt[player];
        if (timePassed < gameCreationInterval) {
            return;
        }

        uint256 addTimes = timePassed / gameCreationInterval;
        if (addTimes + gameTimes[player] >= maxGameTimes) {
            gameTimes[player] = maxGameTimes;
            newGameCountDownStartAt[player] = block.timestamp;
        } else {
            gameTimes[player] = gameTimes[player] + addTimes;
            newGameCountDownStartAt[player] = newGameCountDownStartAt[player] + addTimes * gameCreationInterval;
        }
    }

    function _validGameId(uint256 gameId) internal view returns (bool) {
        return gameId >=0 && gameId < pools.length;
    }

    function _isGameDice(uint gameId, uint diceId) internal view returns (bool) {
        Pool memory pool = pools[gameId];
        for (uint i = 0; i < pool.dices.length; i++) {
            if (pool.dices[i] == diceId) {
                return true;
            }
        }
        return false;
    }

    modifier playable(uint gameId) {
        require(_validGameId(gameId), "invalid game id");
        require(pools[gameId].endTime > block.timestamp, "game ended");
        require(!pools[gameId].success, "game succeeded");
        _;
    }
}