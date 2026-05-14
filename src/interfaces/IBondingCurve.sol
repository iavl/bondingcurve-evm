// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IBondingCurve - Interface for token deployment and trading operations
/// @notice Interface for deploying new tokens and managing their liquidity
interface IBondingCurve {
    struct Pool {
        uint256 virtualEthReserves;
        uint256 virtualTokenReserves;
        uint256 realEthReserves;
        uint256 realTokenReserves;
        uint256 tokenTotalSupply;
        bool complete;
    }

    enum SwapType {
        BUY,
        SELL
    }

    /// @notice Initializes the contract
    /// @param initialVirtualTokenReserves_ Initial virtual token reserves
    /// @param initialVirtualEthReserves_ Initial virtual ETH reserves
    /// @param initialRealTokenReserves_ Initial real token reserves
    /// @param initialRealEthReserves_ Initial real ETH reserves
    /// @param tokenTotalSupply_ Total supply of the token
    /// @param initialOwner_ The address of the initial owner
    function initialize(
        uint256 initialVirtualTokenReserves_,
        uint256 initialVirtualEthReserves_,
        uint256 initialRealTokenReserves_,
        uint256 initialRealEthReserves_,
        uint256 tokenTotalSupply_,
        address initialOwner_
    ) external;

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;

    /// @notice Deploys a new token with specified parameters
    /// @param name Token name
    /// @param symbol Token symbol
    /// @param salt Unique salt for deterministic deployment
    /// @param image The image of the token
    /// @param deployer The address of token deployer
    /// @return token Address of the deployed token
    function deployToken(
        string calldata name,
        string calldata symbol,
        uint256 salt,
        string calldata image,
        address deployer
    ) external returns (address token);

    /// @notice Buy tokens with ETH
    /// @param token Address of the token to buy
    /// @param minTokensReturned The minimum amount of tokens to receive
    /// @return fee The fee paid by ETH
    /// @return tokensReturned The amount of tokens returned to the buyer
    function buy(address token, uint256 minTokensReturned)
        external
        payable
        returns (uint256 fee, uint256 tokensReturned);

    /// @notice Sell tokens for ETH
    /// @param token Address of the token to sell
    /// @param amount Amount of tokens to sell
    /// @param minEthReturned The minimum amount of ETH to receive
    /// @return fee The fee paid by token
    /// @return ethReturned The amount of ETH returned to the seller
    function sell(address token, uint256 amount, uint256 minEthReturned)
        external
        returns (uint256 fee, uint256 ethReturned);

    /// @notice Migrates liquidity to Uniswap V2 pool
    /// @param token Address of the token to migrate liquidity for
    /// @param feeRateBps The fee rate in basis points(700 by recommendation)
    function migrateLiquidity(address token, uint256 feeRateBps) external;

    /// @notice Claims the fee for a token
    /// @param token Address of the token to claim the fee for
    function claimFee(address token) external;

    /// @notice Sets the parameters
    /// @param initialVirtualTokenReserves_ The initial virtual token reserves
    /// @param initialVirtualEthReserves_ The initial virtual ETH reserves
    /// @param initialRealTokenReserves_ The initial real token reserves
    /// @param initialRealEthReserves_ The initial real ETH reserves
    /// @param tokenTotalSupply_ The total supply of the token
    function setParams(
        uint256 initialVirtualTokenReserves_,
        uint256 initialVirtualEthReserves_,
        uint256 initialRealTokenReserves_,
        uint256 initialRealEthReserves_,
        uint256 tokenTotalSupply_
    ) external;

    /// @notice Gets the reserves of a token pool
    /// @param token The address of the token
    function getPool(address token) external view returns (Pool memory);

    /// @notice Gets the buy amount for a token
    /// @param token The address of the token to buy
    /// @param ethAmount The amount of ETH to buy
    /// @return fee The fee paid by ETH
    /// @return tokensReturned The amount of tokens returned to the buyer
    function getBuyAmount(address token, uint256 ethAmount)
        external
        view
        returns (uint256 fee, uint256 tokensReturned);

    /// @notice Gets the sell amount for a token
    /// @param token The address of the token to sell
    /// @param amount The amount of tokens to sell
    /// @return fee The fee paid by tokens
    /// @return ethReturned The amount of ETH returned to the seller
    function getSellAmount(address token, uint256 amount)
        external
        view
        returns (uint256 fee, uint256 ethReturned);

    /// @notice Gets the fee balance for a token and an account
    /// @param token The address of the token
    /// @param account The address of the account
    /// @return The fee balance for the token and account
    function getFeeBalance(address token, address account) external view returns (uint256);

    /// @notice Gets the token deployer for a token
    /// @param token The address of the token
    /// @return The address of the token deployer
    function getTokenDeployer(address token) external view returns (address);

    /// @notice Predicts the address of a deployed token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param salt The salt used for deterministic deployment
    /// @param deployer The address that will deploy the token
    /// @return The predicted address of the deployed token
    function predictToken(
        string calldata name,
        string calldata symbol,
        uint256 salt,
        address deployer
    ) external view returns (address);
}
