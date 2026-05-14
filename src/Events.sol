// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Events - Events for the BondingCurve protocol
/// @notice Contains all events emitted by the protocol
contract Events {
    /// @notice Emitted when a new token is created
    /// @param tokenAddress The address of the created token
    /// @param deployer The address that deployed the token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param supply The total supply of the token
    /// @param image The image of the token
    event TokenCreated(
        address indexed tokenAddress,
        address indexed deployer,
        string name,
        string symbol,
        uint256 supply,
        string image
    );

    /// @notice Emitted when tokens are bought with ETH
    /// @param token The token being bought
    /// @param buyer The address buying the tokens
    /// @param ethAmount The amount of ETH spent (including fees)
    /// @param tokenAmount The amount of tokens received (after fees)
    event Buy(
        address indexed token, address indexed buyer, uint256 indexed ethAmount, uint256 tokenAmount
    );

    /// @notice Emitted when tokens are sold for ETH
    /// @param token The token being sold
    /// @param seller The address selling the tokens
    /// @param tokenAmount The amount of tokens sold (including fees)
    /// @param ethAmount The amount of ETH received (after fees)
    event Sell(
        address indexed token,
        address indexed seller,
        uint256 indexed tokenAmount,
        uint256 ethAmount
    );

    /// @notice Emitted when the funding goal is reached
    /// @param token The token address
    event FundingGoalReached(address indexed token);

    /// @notice Emitted when liquidity is migrated to Uniswap V2
    /// @param token The token address being migrated
    /// @param ethAmount The amount of ETH migrated
    /// @param tokenAmount The amount of tokens migrated
    /// @param liquidity The amount of liquidity created
    event LiquidityMigrated(
        address indexed token,
        uint256 indexed ethAmount,
        uint256 indexed tokenAmount,
        uint256 liquidity
    );

    /// @notice Emitted when a fee is claimed
    /// @param token The token being claimed
    /// @param recipient The address claiming the fee
    /// @param amount The amount of fee claimed
    event FeeClaimed(address indexed token, address indexed recipient, uint256 indexed amount);

    /// @notice Emitted when the global parameters are set
    /// @param initialVirtualTokenReserves The initial virtual token reserves
    /// @param initialVirtualEthReserves The initial virtual ETH reserves
    /// @param initialRealTokenReserves The initial real token reserves
    /// @param initialRealEthReserves The initial real ETH reserves
    /// @param tokenTotalSupply The total supply of the token
    event ParamsSet(
        uint256 indexed initialVirtualTokenReserves,
        uint256 indexed initialVirtualEthReserves,
        uint256 indexed initialRealTokenReserves,
        uint256 initialRealEthReserves,
        uint256 tokenTotalSupply
    );
}
