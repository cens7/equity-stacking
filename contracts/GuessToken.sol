// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract GuessToken is Initializable, ERC20Upgradeable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable, AutomationCompatibleInterface {
    AggregatorV3Interface private btcPriceFeed;

    uint256 public rewardPool;
    uint256 private constant GUESS_DURATION = 10 seconds;

    mapping(address => uint256) private _lockedBalances;
    mapping(address => uint256) private _lockReleaseTime;
    mapping(address => uint256) private _stakedBalances;
    mapping(address => bool) private _isGuessing;
    mapping(address => bool) private _guessedUp;
    mapping(address => uint256) private _guessStartTime;

    event Staked(address indexed user, uint256 amount, bool guessedUp);
    event GuessResolved(address indexed user, uint256 amount, bool metConditionA, uint256 reward);
    event StakeReleased(address indexed user, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _btcPriceFeed) public initializer {
        __ERC20_init("GuessToken", "GUESS");
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        btcPriceFeed = AggregatorV3Interface(_btcPriceFeed);
        rewardPool = 0; // 初始奖励池为0，可以之后通过函数添加
    }

    function stake(uint256 amount, bool guessUp) public {
        require(!_isGuessing[msg.sender], "GuessToken: You have an ongoing guess");
        require(balanceOf(msg.sender) - _lockedBalances[msg.sender] >= amount, "GuessToken: Insufficient balance");

        _stakedBalances[msg.sender] = amount;
        _isGuessing[msg.sender] = true;
        _guessedUp[msg.sender] = guessUp;
        _guessStartTime[msg.sender] = block.timestamp;

        _transfer(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, guessUp);
    }

    function resolveGuess(address user) internal {
        require(_isGuessing[user], "GuessToken: No ongoing guess");
        require(block.timestamp >= _guessStartTime[user] + GUESS_DURATION, "GuessToken: Guess duration not elapsed");

        bool metConditionA = checkConditionA(user);
        uint256 stakedAmount = _stakedBalances[user];
        uint256 reward = 0;

        if (metConditionA) {
            reward = stakedAmount * 20 / 100;
            require(rewardPool >= reward, "GuessToken: Insufficient reward pool");
            rewardPool -= reward;
            _transfer(address(this), user, stakedAmount + reward);
        } else {
            uint256 penalty = stakedAmount * 20 / 100;
            rewardPool += penalty;
            _transfer(address(this), user, stakedAmount - penalty);
        }

        _stakedBalances[user] = 0;
        _isGuessing[user] = false;

        emit GuessResolved(user, stakedAmount, metConditionA, reward);
        emit StakeReleased(user, stakedAmount);
    }

    function checkConditionA(address user) private view returns (bool) {
        (uint80 roundId, int256 startPrice, , uint256 startTimestamp, ) = btcPriceFeed.latestRoundData();
        require(startTimestamp <= _guessStartTime[user], "GuessToken: Invalid start time");

        (uint80 endRoundId, int256 endPrice, , , ) = btcPriceFeed.getRoundData(roundId + 1);
        require(endRoundId > roundId, "GuessToken: End round not available");

        bool priceIncreased = endPrice > startPrice;
        return priceIncreased == _guessedUp[user];
    }

    function checkUpkeep(bytes calldata /* checkData */) external view override returns (bool upkeepNeeded, bytes memory /* performData */) {
        address[] memory guessingUsers = getGuessingUsers();
        for (uint i = 0; i < guessingUsers.length; i++) {
            if (block.timestamp >= _guessStartTime[guessingUsers[i]] + GUESS_DURATION) {
                return (true, abi.encode(guessingUsers[i]));
            }
        }
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override {
        address userToResolve = abi.decode(performData, (address));
        resolveGuess(userToResolve);
    }

    function getGuessingUsers() public view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < balanceOf(address(this)); i++) {
            if (_isGuessing[address(uint160(i))]) {
                count++;
            }
        }
        address[] memory guessingUsers = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < balanceOf(address(this)); i++) {
            if (_isGuessing[address(uint160(i))]) {
                guessingUsers[index] = address(uint160(i));
                index++;
            }
        }
        return guessingUsers;
    }

    function addToRewardPool(uint256 amount) public onlyOwner {
        rewardPool += amount;
        _mint(address(this), amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
    internal
    override
    whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyOwner
    {}
}