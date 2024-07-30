// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract GuessToken is ERC20, Pausable, Ownable, AutomationCompatibleInterface {
    AggregatorV3Interface private btcPriceFeed;

    uint256 public rewardPool;
    uint256 private constant GUESS_DURATION = 10 seconds;
    uint256 private constant MIN_STAKE_AMOUNT = 10000 * 10**18; // 最少质押10000个代币
    uint256 private constant TOKENS_PER_ETH = 10000000000 * 10**18; // 0.00001 ETH 兑换 100000000 个代币
    uint256 private constant MIN_PURCHASE_ETH = 10000000000000; // 0.00001 ETH in wei
    uint256 private constant MAX_DAILY_EXCHANGE_PER_USER = 200000000000000; // 0.0002 ETH in wei
    uint256 private constant MAX_DAILY_EXCHANGE_TOTAL = 2000000000000000; // 0.002 ETH in wei

    mapping(address => uint256) private _lockedBalances;
    mapping(address => uint256) private _lockReleaseTime;
    mapping(address => uint256) private _stakedBalances;
    mapping(address => bool) private _isGuessing;
    mapping(address => bool) private _guessedUp;
    mapping(address => uint256) private _guessStartTime;
    mapping(address => bool) private _hasParticipated;
    mapping(address => uint256) private _lastExchangeTime;
    mapping(address => uint256) private _dailyExchangeAmount;
    uint256 private _totalDailyExchange;
    uint256 private _lastDailyResetTime;

    event Staked(address indexed user, uint256 amount, bool guessedUp);
    event GuessResolved(address indexed user, uint256 amount, bool metConditionA, uint256 reward);
    event StakeReleased(address indexed user, uint256 amount);
    event TokensPurchased(address indexed buyer, uint256 ethAmount, uint256 tokenAmount);
    event TokensExchanged(address indexed seller, uint256 tokenAmount, uint256 ethAmount);

    constructor(address _btcPriceFeed) ERC20("GuessToken", "GUESS") {
        require(_btcPriceFeed != address(0), "Invalid price feed address");
        btcPriceFeed = AggregatorV3Interface(_btcPriceFeed);
        rewardPool = 0;
        _lastDailyResetTime = block.timestamp;
    }

    function purchaseTokens() public payable {
        require(msg.value >= MIN_PURCHASE_ETH, "Must send at least 0.00001 ETH");
        uint256 tokensToMint = (msg.value * TOKENS_PER_ETH) / (1 ether);
        _mint(msg.sender, tokensToMint);
        emit TokensPurchased(msg.sender, msg.value, tokensToMint);
    }

    function exchangeTokensForEth(uint256 tokenAmount) public {
        require(_hasParticipated[msg.sender], "Must have participated in guessing game");
        require(tokenAmount >= TOKENS_PER_ETH, "Must exchange at least 100000000 tokens");

        uint256 ethToSend = (tokenAmount * 1 ether) / TOKENS_PER_ETH;
        require(ethToSend <= MAX_DAILY_EXCHANGE_PER_USER, "Exceeds daily exchange limit per user");

        _resetDailyExchangeIfNeeded();

        require(_totalDailyExchange + ethToSend <= MAX_DAILY_EXCHANGE_TOTAL, "Exceeds total daily exchange limit");

        require(address(this).balance >= ethToSend, "Insufficient ETH in contract");

        _burn(msg.sender, tokenAmount);
        _totalDailyExchange += ethToSend;
        _dailyExchangeAmount[msg.sender] += ethToSend;
        _lastExchangeTime[msg.sender] = block.timestamp;

        payable(msg.sender).transfer(ethToSend);

        emit TokensExchanged(msg.sender, tokenAmount, ethToSend);
    }

    function _resetDailyExchangeIfNeeded() private {
        if (block.timestamp >= _lastDailyResetTime + 1 days) {
            _totalDailyExchange = 0;
            _lastDailyResetTime = block.timestamp;
        }
    }

    function stake(uint256 amount, bool guessUp) public {
        require(!_isGuessing[msg.sender], "GuessToken: You have an ongoing guess");
        require(amount >= MIN_STAKE_AMOUNT, "GuessToken: Stake amount too low");
        require(balanceOf(msg.sender) >= amount, "GuessToken: Insufficient balance");

        _stakedBalances[msg.sender] = amount;
        _isGuessing[msg.sender] = true;
        _guessedUp[msg.sender] = guessUp;
        _guessStartTime[msg.sender] = block.timestamp;
        _hasParticipated[msg.sender] = true;

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

    receive() external payable {
        purchaseTokens();
    }
}