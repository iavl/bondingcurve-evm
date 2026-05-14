// SPDX-License-Identifier: MIT
// solhint-disable immutable-vars-naming
pragma solidity 0.8.26;

import {
    InsufficientOutput,
    InvalidFeeRate,
    NoFeeToClaim,
    NotAgent,
    PoolComplete,
    PoolIncomplete,
    ZeroAmount,
    ZeroAmountReturn
} from "./Errors.sol";
import {Events} from "./Events.sol";
import {Token} from "./Token.sol";
import {IBondingCurve} from "./interfaces/IBondingCurve.sol";
import {IUniswapV2Router} from "./interfaces/IUniswapV2Router.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Bytes32AddressLib} from "@solmate/utils/Bytes32AddressLib.sol";

// import {console} from "forge-std/console.sol";

/// @title BondingCurve - A decentralized bonding curve for token launches
/// @notice This contract manages token deployments and liquidity pools
/// @dev Implements a custom bonding curve with virtual reserves for price discovery
contract BondingCurve is IBondingCurve, Events, OwnableUpgradeable, PausableUpgradeable {
    using Bytes32AddressLib for bytes32;
    using Address for address;
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant FEE_RATE_BPS = 200; // 2%
    uint256 public constant MAX_FEE_RATE_BPS = 1000; // 10%
    uint256 public constant DENOMINATOR = 10_000;
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public immutable uniswapV2Router;
    // Wallets
    address public immutable agent;
    address public immutable dev;

    // Storage
    mapping(address token => Pool pool) internal _pools;
    mapping(address token => address deployer) internal _tokenDeployers;
    mapping(address token => mapping(address account => uint256 feeBalance)) internal _feeBalances;
    // global config
    uint256 public initialVirtualTokenReserves;
    uint256 public initialVirtualEthReserves;
    uint256 public initialRealTokenReserves;
    uint256 public initialRealEthReserves;
    uint256 public tokenTotalSupply;

    // Modifiers
    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent();
        _;
    }

    /// @dev Constructor
    /// @param uniswapV2Router_ Address of the Uniswap V2 router
    /// @param agent_ Address of the agent wallet
    /// @param dev_ Address of the team wallet
    constructor(address uniswapV2Router_, address agent_, address dev_) {
        uniswapV2Router = uniswapV2Router_;

        agent = agent_;
        dev = dev_;
    }

    /// @inheritdoc IBondingCurve
    function initialize(
        uint256 initialVirtualTokenReserves_,
        uint256 initialVirtualEthReserves_,
        uint256 initialRealTokenReserves_,
        uint256 initialRealEthReserves_,
        uint256 tokenTotalSupply_,
        address initialOwner_
    ) external override initializer {
        initialVirtualTokenReserves = initialVirtualTokenReserves_;
        initialVirtualEthReserves = initialVirtualEthReserves_;
        initialRealTokenReserves = initialRealTokenReserves_;
        initialRealEthReserves = initialRealEthReserves_;
        tokenTotalSupply = tokenTotalSupply_;

        __Ownable_init(initialOwner_);
        __Pausable_init();
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }

    /// @inheritdoc IBondingCurve
    function deployToken(
        string calldata name,
        string calldata symbol,
        uint256 salt_,
        string calldata image,
        address deployer
    ) external override onlyAgent whenNotPaused returns (address token) {
        token = address(
            new Token{salt: keccak256(abi.encode(deployer, salt_))}(name, symbol, tokenTotalSupply)
        );

        _createPool(token);

        _tokenDeployers[token] = deployer;

        emit TokenCreated(token, deployer, name, symbol, tokenTotalSupply, image);
    }

    /// @inheritdoc IBondingCurve
    function buy(address token, uint256 minTokensReturned)
        external
        payable
        override
        whenNotPaused
        returns (uint256 fee, uint256 tokensReturned)
    {
        if (msg.value == 0) revert ZeroAmount();

        (fee, tokensReturned) = _swap(token, SwapType.BUY, msg.value, minTokensReturned, msg.sender);

        emit Buy(token, msg.sender, msg.value, tokensReturned);
    }

    /// @inheritdoc IBondingCurve
    function sell(address token, uint256 amount, uint256 minEthReturned)
        external
        override
        whenNotPaused
        returns (uint256 fee, uint256 ethReturned)
    {
        if (amount == 0) revert ZeroAmount();

        (fee, ethReturned) = _swap(token, SwapType.SELL, amount, minEthReturned, msg.sender);

        emit Sell(token, msg.sender, amount, ethReturned);
    }

    /// @inheritdoc IBondingCurve
    function migrateLiquidity(address token, uint256 feeRateBps)
        external
        override
        onlyAgent
        whenNotPaused
    {
        // fee rate must be less than 10%
        if (feeRateBps > MAX_FEE_RATE_BPS) revert InvalidFeeRate();

        Pool memory pool = _pools[token];
        if (!pool.complete) revert PoolIncomplete();

        // Calculate and distribute migration fee
        uint256 migrationFeeEth = (pool.realEthReserves * feeRateBps) / DENOMINATOR;
        _distributeMigrationFee(migrationFeeEth, token);

        // Calculate available tokens and ETH for liquidity
        uint256 availableEth = pool.realEthReserves - migrationFeeEth;
        uint256 availableTokens = _getAvailableTokens(token);
        // console.log("token price after migration", availableEth * 1 ether / availableTokens);

        // Clear pool reserves
        _clearPool(token);

        // Approve uniswapV2Router to spend tokens
        IERC20(token).approve(uniswapV2Router, availableTokens);

        // Add liquidity through router
        (uint256 tokensUsed, uint256 ethUsed, uint256 lpTokens) = IUniswapV2Router(uniswapV2Router)
        .addLiquidityETH{value: availableEth}(
            token,
            availableTokens,
            0, // Accept any amount of tokens
            0, // Accept any amount of ETH
            address(0), // LP tokens go to null address
            block.timestamp
        );

        emit LiquidityMigrated(token, ethUsed, tokensUsed, lpTokens);
    }

    /// @inheritdoc IBondingCurve
    function claimFee(address token) external override whenNotPaused {
        uint256 fee = _feeBalances[token][msg.sender];
        if (fee == 0) revert NoFeeToClaim();

        _feeBalances[token][msg.sender] = 0;
        _transfer(token, msg.sender, fee);

        emit FeeClaimed(token, msg.sender, fee);
    }

    /// @inheritdoc IBondingCurve
    function setParams(
        uint256 initialVirtualTokenReserves_,
        uint256 initialVirtualEthReserves_,
        uint256 initialRealTokenReserves_,
        uint256 initialRealEthReserves_,
        uint256 tokenTotalSupply_
    ) external override onlyOwner {
        initialVirtualTokenReserves = initialVirtualTokenReserves_;
        initialVirtualEthReserves = initialVirtualEthReserves_;
        initialRealTokenReserves = initialRealTokenReserves_;
        initialRealEthReserves = initialRealEthReserves_;
        tokenTotalSupply = tokenTotalSupply_;

        emit ParamsSet(
            initialVirtualTokenReserves_,
            initialVirtualEthReserves_,
            initialRealTokenReserves_,
            initialRealEthReserves_,
            tokenTotalSupply_
        );
    }

    /// @inheritdoc IBondingCurve
    function getPool(address token) external view override returns (Pool memory) {
        return _pools[token];
    }

    /// @inheritdoc IBondingCurve
    function getBuyAmount(address token, uint256 ethAmount)
        external
        view
        override
        returns (uint256 fee, uint256 tokensReturned)
    {
        Pool memory pool = _pools[token];
        (fee,, tokensReturned) = _getAmountOut(ethAmount, SwapType.BUY, pool);
    }

    /// @inheritdoc IBondingCurve
    function getSellAmount(address token, uint256 amount)
        external
        view
        override
        returns (uint256 fee, uint256 ethReturned)
    {
        Pool memory pool = _pools[token];
        (fee,, ethReturned) = _getAmountOut(amount, SwapType.SELL, pool);
    }

    /// @inheritdoc IBondingCurve
    function getFeeBalance(address token, address account)
        external
        view
        override
        returns (uint256)
    {
        return _feeBalances[token][account];
    }

    /// @inheritdoc IBondingCurve
    function getTokenDeployer(address token) external view override returns (address) {
        return _tokenDeployers[token];
    }

    /// @inheritdoc IBondingCurve
    function predictToken(
        string calldata name,
        string calldata symbol,
        uint256 salt,
        address deployer
    ) external view override returns (address) {
        bytes32 create2Salt = keccak256(abi.encode(deployer, salt));
        return keccak256(
                abi.encodePacked(
                    bytes1(0xFF),
                    address(this),
                    create2Salt,
                    keccak256(
                        abi.encodePacked(
                            type(Token).creationCode, abi.encode(name, symbol, tokenTotalSupply)
                        )
                    )
                )
            ).fromLast20Bytes();
    }

    function _createPool(address token) internal {
        Pool storage pool = _pools[token];
        pool.virtualEthReserves = initialVirtualEthReserves;
        pool.virtualTokenReserves = initialVirtualTokenReserves;
        pool.realTokenReserves = initialRealTokenReserves;
        pool.realEthReserves = 0;
        pool.tokenTotalSupply = tokenTotalSupply;
    }

    function _clearPool(address token) internal {
        Pool storage pool = _pools[token];
        pool.virtualEthReserves = 0;
        pool.virtualTokenReserves = 0;
        pool.realTokenReserves = 0;
        pool.realEthReserves = 0;
    }

    /// @dev Common swap logic for both buy and sell operations
    /// @param token The token address
    /// @param swapType The type of swap operation: buy or sell
    /// @param amountIn The input amount (ETH for buy, tokens for sell)
    /// @param amountOutMin Minimum amount expected in return
    /// @param user The user address
    function _swap(
        address token,
        SwapType swapType,
        uint256 amountIn,
        uint256 amountOutMin,
        address user
    ) internal returns (uint256 fee, uint256 amountOut) {
        if (amountOutMin == 0) revert ZeroAmountReturn();

        Pool storage pool = _pools[token];
        if (pool.complete) revert PoolComplete();

        uint256 amountWithFee;
        (fee, amountWithFee, amountOut) = _getAmountOut(amountIn, swapType, pool);
        if (amountOut < amountOutMin) revert InsufficientOutput();

        // Update pool reserves
        if (SwapType.BUY == swapType) {
            pool.virtualEthReserves += amountWithFee;
            pool.realEthReserves += amountWithFee;
            pool.virtualTokenReserves -= amountOut;
            pool.realTokenReserves -= amountOut;

            // the funding goal is reached
            if (pool.realTokenReserves <= 2000 ether) {
                pool.complete = true;

                emit FundingGoalReached(token);
            }

            // transfer tokens to user
            _transfer(token, user, amountOut);
            // distribute fee ETH
            _distributeSwapFee(ETH_ADDRESS, fee);
        } else {
            pool.realEthReserves -= amountOut;
            pool.virtualEthReserves -= amountOut;
            pool.realTokenReserves += amountWithFee;
            pool.virtualTokenReserves += amountWithFee;

            IERC20(token).safeTransferFrom(user, address(this), amountIn);
            // transfer ETH to user
            _transfer(ETH_ADDRESS, user, amountOut);
            // distribute fee tokens
            _distributeSwapFee(token, fee);
        }
    }

    /// @dev Distributes the fee to the agent and team wallets
    function _distributeSwapFee(address token, uint256 fee) internal {
        if (fee > 0) {
            uint256 agentFee = fee / 2;

            _feeBalances[token][agent] += agentFee;
            _feeBalances[token][dev] += fee - agentFee;
        }
    }

    /// @dev Distributes the fee to the agent, deployer and team wallets
    function _distributeMigrationFee(uint256 feeEth, address token) internal {
        if (feeEth > 0) {
            uint256 agentFee = feeEth / 3;
            uint256 deployerFee = feeEth / 3;

            _feeBalances[ETH_ADDRESS][agent] += agentFee;
            _feeBalances[ETH_ADDRESS][_tokenDeployers[token]] += deployerFee;
            _feeBalances[ETH_ADDRESS][dev] += feeEth - agentFee - deployerFee;
        }
    }

    /// @dev _transfer should always be at the end of the function,
    /// to apply the checks-effects-interactions pattern
    function _transfer(address token, address to, uint256 amount) internal {
        if (token == ETH_ADDRESS) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @dev Calculates the available token amount for liquidity
    /// @param token The token address
    /// @return The available token amount
    function _getAvailableTokens(address token) internal view returns (uint256) {
        // Calculate available token amount for liquidity
        uint256 totalClaimableFees = _feeBalances[token][agent] + _feeBalances[token][dev];
        uint256 theoreticalAvailable = tokenTotalSupply - initialRealTokenReserves;
        uint256 actualBalance = IERC20(token).balanceOf(address(this)) - totalClaimableFees;
        return Math.min(theoreticalAvailable, actualBalance);
    }

    /// @dev Calculates the fee, net amount after fee deduction and amount returned
    /// for a given input amount in a swap operation
    /// @param amountIn The input amount
    /// @param swapType The type of swap operation
    /// @param pool The pool reserves
    function _getAmountOut(uint256 amountIn, SwapType swapType, Pool memory pool)
        internal
        pure
        returns (uint256 fee, uint256 amountWithFee, uint256 amountOut)
    {
        (fee, amountWithFee) = _calculateFeeAndNet(amountIn);
        amountOut = (SwapType.BUY == swapType)
            ? _calculateSwapAmount(
                amountWithFee,
                pool.virtualEthReserves,
                pool.virtualTokenReserves,
                pool.realTokenReserves
            )
            : _calculateSwapAmount(
                amountWithFee,
                pool.virtualTokenReserves,
                pool.virtualEthReserves,
                pool.realEthReserves
            );
    }

    /// @dev Calculates fee and net amount after fee deduction
    /// @param amount The gross amount
    /// @return fee The calculated fee amount
    /// @return amountWithFee The net amount after fee deduction
    function _calculateFeeAndNet(uint256 amount)
        internal
        pure
        returns (uint256 fee, uint256 amountWithFee)
    {
        fee = (amount * FEE_RATE_BPS) / DENOMINATOR;
        amountWithFee = amount - fee;
    }

    /// @dev Calculates the amount returned for a swap using constant product formula
    /// @param amountIn The input amount (after fee deduction)
    /// @param reserveIn The virtual reserve of the input token
    /// @param reserveOut The virtual reserve of the output token
    /// @param realReserveOut The real reserve of the output token
    /// @return amountOut The amount of output tokens to be returned
    function _calculateSwapAmount(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 realReserveOut
    ) internal pure returns (uint256 amountOut) {
        if (reserveIn == 0 || reserveOut == 0) return 0;

        uint256 k = reserveIn * reserveOut;
        uint256 newReserveIn = reserveIn + amountIn;
        uint256 newReserveOut = k / newReserveIn;
        amountOut = reserveOut - newReserveOut;

        if (amountOut > realReserveOut) {
            amountOut = realReserveOut;
        }
    }
}
