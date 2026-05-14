// SPDX-License-Identifier: MIT
// solhint-disable comprehensive-interface,no-console,function-max-lines
pragma solidity 0.8.26;

import {DeployConfig} from "../script/DeployConfig.s.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {
    InsufficientOutput,
    InvalidFeeRate,
    NoFeeToClaim,
    NotAgent,
    PoolComplete,
    ZeroAmount,
    ZeroAmountReturn
} from "../src/Errors.sol";
import {Events} from "../src/Events.sol";
import {IBondingCurve} from "../src/interfaces/IBondingCurve.sol";
import {IUniswapV2Router} from "../src/interfaces/IUniswapV2Router.sol";
import {Utils} from "./Utils.sol";
import {
    TransparentUpgradeableProxy as Proxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract BondingCurveTest is Utils, Events {
    using Strings for uint256;

    DeployConfig internal _cfg;
    BondingCurve public bondingCurve;

    address public constant weth = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant uniswapV2Router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant uniswapV2Factory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");
    string public constant name = "Test";
    string public constant symbol = "TEST";

    error InvalidInitialization();
    error OwnableUnauthorizedAccount(address account);
    error EnforcedPause();

    function setUp() public {
        _setup();

        vm.deal(alice, 100 ether);
    }

    function testReInitializeFails() public {
        vm.expectRevert(InvalidInitialization.selector);
        bondingCurve.initialize(1, 1, 1, 1, 1, address(0xabcde));
    }

    function testPauseSucceeds() public {
        vm.prank(bondingCurve.owner());
        bondingCurve.pause();

        assertTrue(bondingCurve.paused());
    }

    function testPauseFailsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        bondingCurve.pause();
    }

    function testUnpauseSucceeds() public {
        vm.prank(bondingCurve.owner());
        bondingCurve.pause();

        vm.prank(bondingCurve.owner());
        bondingCurve.unpause();

        assertFalse(bondingCurve.paused());
    }

    function testUnpauseFailsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        bondingCurve.unpause();
    }

    function testWhenPaused() public {
        vm.prank(bondingCurve.owner());
        bondingCurve.pause();

        address agentWallet = bondingCurve.agent();

        vm.expectRevert(EnforcedPause.selector);
        vm.prank(agentWallet);
        bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        vm.expectRevert(EnforcedPause.selector);
        bondingCurve.buy{value: 1 ether}(address(1), 1);

        vm.expectRevert(EnforcedPause.selector);
        bondingCurve.sell(address(1), 1, 1);

        vm.expectRevert(EnforcedPause.selector);
        vm.prank(agentWallet);
        bondingCurve.migrateLiquidity(address(1), 1);

        vm.expectRevert(EnforcedPause.selector);
        bondingCurve.claimFee(address(1));
    }

    function testDeployTokenSucceeds() public {
        uint256 salt = 0;
        string memory image = "https://example.com/image.png";
        address agentWallet = bondingCurve.agent();

        address expectedToken = bondingCurve.predictToken(name, symbol, salt, alice);
        expectEmit();
        emit TokenCreated(
            expectedToken, alice, name, symbol, bondingCurve.tokenTotalSupply(), image
        );
        vm.prank(agentWallet);
        (address token) = bondingCurve.deployToken(name, symbol, salt, image, alice);

        // check token state
        assertEq(token, expectedToken);
        assertEq(IERC20(token).name(), name);
        assertEq(IERC20(token).symbol(), symbol);
        assertEq(IERC20(token).decimals(), 18);
        assertEq(IERC20(token).totalSupply(), bondingCurve.tokenTotalSupply());
        assertEq(IERC20(token).balanceOf(address(bondingCurve)), bondingCurve.tokenTotalSupply());

        assertEq(bondingCurve.getTokenDeployer(token), alice);

        // check pool state
        IBondingCurve.Pool memory pool = bondingCurve.getPool(token);
        assertEq(pool.realEthReserves, 0);
        assertEq(pool.realTokenReserves, bondingCurve.initialRealTokenReserves());
        assertEq(pool.virtualEthReserves, bondingCurve.initialVirtualEthReserves());
        assertEq(pool.virtualTokenReserves, bondingCurve.initialVirtualTokenReserves());
        assertEq(pool.tokenTotalSupply, bondingCurve.tokenTotalSupply());
    }

    function testDeployTokenFailTwice() public {
        vm.startPrank(bondingCurve.agent());
        bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        vm.expectRevert();
        bondingCurve.deployToken(name, symbol, uint256(1), "", alice);
        vm.stopPrank();
    }

    function testBuySucceeds(uint256 ethAmount) public {
        ethAmount = bound(ethAmount, 1, 10 ether);

        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        // buy token
        (uint256 expectedFee, uint256 expectedTokensReturned) =
            bondingCurve.getBuyAmount(token, ethAmount);
        expectEmit();
        emit Buy(token, alice, ethAmount, expectedTokensReturned);
        vm.prank(alice);
        (uint256 fee, uint256 tokensReturned) =
            bondingCurve.buy{value: ethAmount}(token, expectedTokensReturned);

        // check token state
        uint256 tokenBalance = IERC20(token).balanceOf(alice);
        assertEq(tokenBalance, tokensReturned, "tokenBalance != tokensReturned");
        assertEq(expectedTokensReturned, tokensReturned, "expectedTokensReturned != tokensReturned");
        assertEq(expectedFee, fee, "expectedFee != fee");

        // check pool state
        IBondingCurve.Pool memory pool = bondingCurve.getPool(token);
        assertEq(pool.realEthReserves, ethAmount - fee, "pool.realEthReserves != ethAmount - fee");
        assertEq(
            pool.realTokenReserves,
            bondingCurve.initialRealTokenReserves() - tokensReturned,
            "pool.realTokenReserves != bondingCurve.initialRealTokenReserves() - tokensReturned"
        );
        assertEq(
            pool.virtualEthReserves,
            bondingCurve.initialVirtualEthReserves() + ethAmount - fee,
            "pool.virtualEthReserves != bondingCurve.initialVirtualEthReserves() + ethAmount - fee"
        );
        assertEq(
            pool.virtualTokenReserves,
            bondingCurve.initialVirtualTokenReserves() - tokensReturned,
            "pool.virtualTokenReserves != bondingCurve.initialVirtualTokenReserves() - tokensReturned"
        );

        // check fee balance
        address agentWallet = bondingCurve.agent();
        address devWallet = bondingCurve.dev();
        address feeToken = bondingCurve.ETH_ADDRESS();
        assertEq(
            bondingCurve.getFeeBalance(feeToken, agentWallet),
            fee / 2,
            "bondingCurve.getFeeBalance(feeToken, agentWallet) != fee / 2"
        );
        assertEq(
            bondingCurve.getFeeBalance(feeToken, devWallet),
            fee - (fee / 2),
            "bondingCurve.getFeeBalance(feeToken, devWallet) != fee - (fee / 2)"
        );
    }

    // solhint-disable-next-line function-max-lines
    function testBuyAllTokensSucceeds() public {
        uint256 ethTokenPrice = 3660;
        uint256 ethAmount = 0.01 ether;

        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        // buy tokens with 0.1 ether each, for 58 times
        uint256 totalCount = 580;
        uint256 totalTokensBought;
        for (uint256 i = 1; i <= totalCount; i++) {
            vm.prank(alice);
            (, uint256 tokensReturned) = bondingCurve.buy{value: ethAmount}(token, 1);
            totalTokensBought += tokensReturned;

            uint256 virtualTokenReserves = bondingCurve.getPool(token).virtualTokenReserves;
            uint256 virtualEthReserves = bondingCurve.getPool(token).virtualEthReserves;
            uint256 realTokenReserves = bondingCurve.getPool(token).realTokenReserves;
            uint256 realEthReserves = bondingCurve.getPool(token).realEthReserves;
            uint256 tokenMarketCap = bondingCurve.tokenTotalSupply() * ethTokenPrice
                * virtualEthReserves / virtualTokenReserves;
            if (i == 1) {
                console.log("Iteration\tEthReserves\tTokenReserves\tMarketCap\tTokenSold");
            }
            console.log(
                string(
                    abi.encodePacked(
                        i.toString(),
                        "\t",
                        realEthReserves.toString(),
                        "\t",
                        (realTokenReserves / 1 ether).toString(),
                        "\t",
                        (tokenMarketCap / 1 ether).toString(),
                        "\t",
                        ((bondingCurve.initialRealTokenReserves() - realTokenReserves) / 1 ether)
                        .toString()
                    )
                )
            );

            if (i >= totalCount) {
                console.log("================ migrateLiquidity ================");
                console.log("priceBefore \tpriceAfter \t priceDelta(-%)");
                uint256 priceBefore = virtualEthReserves * 1e15 / virtualTokenReserves;
                uint256 priceAfter = realEthReserves * 1e15 * 93 / 100
                    / (IERC20(token).balanceOf(address(bondingCurve)));
                console.log(
                    string(
                        abi.encodePacked(
                            priceBefore.toString(),
                            "\t\t",
                            priceAfter.toString(),
                            "\t\t ",
                            ((priceBefore - priceAfter) * 100 / priceBefore).toString()
                        )
                    )
                );
            }

            assertEq(IERC20(token).balanceOf(alice), totalTokensBought);
            assertEq(
                bondingCurve.getPool(token).realTokenReserves,
                bondingCurve.initialRealTokenReserves() - totalTokensBought
            );
        }

        assertTrue(bondingCurve.getPool(token).complete);
    }

    function testFundingGoalReached() public {
        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        expectEmit();
        emit FundingGoalReached(token);
        vm.prank(alice);
        bondingCurve.buy{value: 5.8 ether}(token, 700_000_000 ether);
    }

    function testBuyFailZeroAmount() public {
        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        // case 1: ZeroAmount
        vm.expectRevert(ZeroAmount.selector);
        bondingCurve.buy{value: 0}(token, 1);

        // case 2: ZeroAmountReturn
        vm.expectRevert(ZeroAmountReturn.selector);
        bondingCurve.buy{value: 0.1 ether}(token, 0);
    }

    function testBuyFailInsufficientOutput() public {
        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        vm.expectRevert(InsufficientOutput.selector);
        vm.prank(alice);
        bondingCurve.buy{value: 0.1 ether}(token, 900_000_000 ether);

        vm.expectRevert(InsufficientOutput.selector);
        vm.prank(alice);
        bondingCurve.buy{value: 0.1 ether}(address(1), 1);
    }

    function testBuyFailTokenNotDeployed() public {
        address token = bondingCurve.predictToken(name, symbol, 0, alice);

        vm.expectRevert(InsufficientOutput.selector);
        vm.prank(alice);
        bondingCurve.buy{value: 1 ether}(token, 900_000_000 ether);
    }

    function testBuyFailWhenPoolIsComplete() public {
        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        bondingCurve.buy{value: 6 ether}(token, 1 ether);

        vm.expectRevert(PoolComplete.selector);
        vm.prank(alice);
        bondingCurve.buy{value: 1 ether}(token, 900_000_000 ether);
    }

    function testSellSucceeds() public {
        uint256 ethAmount = 5 ether;

        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        vm.startPrank(alice);
        // buy tokens
        (uint256 feeByEth, uint256 tokensReturned) =
            bondingCurve.buy{value: ethAmount}(token, 1 ether);
        console.log("ethAmount", ethAmount - feeByEth, "tokensReturned", tokensReturned);
        console.log("fee by eth", feeByEth);

        // approve
        IERC20(token).approve(address(bondingCurve), tokensReturned);

        // sell all tokens
        (uint256 expectedFee, uint256 expectedEthReturned) =
            bondingCurve.getSellAmount(token, tokensReturned);
        expectEmit();
        emit Sell(token, alice, tokensReturned, expectedEthReturned);
        (uint256 feeByToken, uint256 ethReturned) = bondingCurve.sell(token, tokensReturned, 1);
        vm.stopPrank();
        console.log("tokenAmount", tokensReturned - feeByToken, "ethReturned", ethReturned);

        // check token state
        console.log("check token state");
        assertEq(IERC20(token).balanceOf(alice), 0);
        assertEq(expectedEthReturned, ethReturned);
        assertEq(expectedFee, feeByToken);

        uint256 deltaEthReserves = (ethAmount - feeByEth) - ethReturned;
        uint256 deltaTokenReserves = feeByToken;

        // check pool state
        console.log("check pool state");
        IBondingCurve.Pool memory pool = bondingCurve.getPool(token);
        // console.log("pool.realEthReserves", pool.realEthReserves);
        // console.log("pool.realTokenReserves", pool.realTokenReserves);
        // console.log("pool.virtualEthReserves", pool.virtualEthReserves);
        // console.log("pool.virtualTokenReserves", pool.virtualTokenReserves);
        assertEq(pool.realEthReserves, deltaEthReserves);
        assertEq(
            pool.realTokenReserves, bondingCurve.initialRealTokenReserves() - deltaTokenReserves
        );
        assertEq(
            pool.virtualEthReserves, bondingCurve.initialVirtualEthReserves() + deltaEthReserves
        );
        assertEq(
            pool.virtualTokenReserves,
            bondingCurve.initialVirtualTokenReserves() - deltaTokenReserves
        );

        // check fee balance
        console.log("check fee balance");
        console.log("fee by token", feeByToken);
        address agentWallet = bondingCurve.agent();
        address devWallet = bondingCurve.dev();
        address feeToken = token;
        assertEq(bondingCurve.getFeeBalance(feeToken, agentWallet), feeByToken / 2);
        assertEq(bondingCurve.getFeeBalance(feeToken, devWallet), feeByToken - (feeByToken / 2));
    }

    function testSellAllTokensSucceeds() public {
        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        vm.startPrank(alice);
        bondingCurve.buy{value: 5 ether}(token, 1);

        // sell all tokens
        uint256 tokenBalance = IERC20(token).balanceOf(alice);
        IERC20(token).approve(address(bondingCurve), tokenBalance);

        (uint256 expectedFeeByToken, uint256 expectedEthReturned) =
            bondingCurve.getSellAmount(token, tokenBalance);
        expectEmit();
        emit Sell(token, alice, tokenBalance, expectedEthReturned);
        (uint256 feeByToken, uint256 ethReturned) = bondingCurve.sell(token, tokenBalance, 1);
        vm.stopPrank();

        // check fee
        assertEq(feeByToken, expectedFeeByToken);
        assertEq(ethReturned, expectedEthReturned);
        assertEq(feeByToken, tokenBalance * 2 / 100);
        assertEq(IERC20(token).balanceOf(alice), 0);

        // check pool state
        IBondingCurve.Pool memory pool = bondingCurve.getPool(token);
        assertEq(pool.realTokenReserves + feeByToken, bondingCurve.initialRealTokenReserves());
        assertEq(pool.virtualTokenReserves + feeByToken, bondingCurve.initialVirtualTokenReserves());
    }

    function testSellFailInsufficientOutput() public {
        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        vm.startPrank(alice);
        bondingCurve.buy{value: 1 ether}(token, 1 ether);
        IERC20(token).approve(address(bondingCurve), 1 ether);

        vm.expectRevert(InsufficientOutput.selector);
        bondingCurve.sell(token, 1 ether, 10_000 ether);
        vm.stopPrank();
    }

    function testSellFailTokenNotDeployed() public {
        vm.expectRevert(InsufficientOutput.selector);
        bondingCurve.sell(address(1), 1 ether, 1);
    }

    function testSellFailZeroAmountReturn() public {
        vm.expectRevert(ZeroAmountReturn.selector);
        bondingCurve.sell(address(1), 1 ether, 0);
    }

    function testSellFailWhenPoolIsComplete() public {
        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        bondingCurve.buy{value: 6 ether}(token, 1 ether);

        vm.prank(alice);
        IERC20(token).approve(address(bondingCurve), 100 ether);
        vm.expectRevert(PoolComplete.selector);
        vm.prank(alice);
        bondingCurve.sell(token, 100 ether, 1);
    }

    function testMigrateLiquiditySucceeds() public {
        uint256 ethAmount = 5.8 ether;
        address agentWallet = bondingCurve.agent();
        address devWallet = bondingCurve.dev();
        address feeToken = bondingCurve.ETH_ADDRESS();

        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", address(0xabcde));

        // buy all tokens
        vm.prank(alice);
        bondingCurve.buy{value: ethAmount}(token, 1);

        IBondingCurve.Pool memory pool = bondingCurve.getPool(token);
        uint256 swapFee = ethAmount * 2 / 100;
        uint256 migrationFee = (ethAmount - swapFee) * 7 / 100;
        uint256 expectedEthUsed = ethAmount - swapFee - migrationFee;
        uint256 expectedTokenUsed =
            bondingCurve.tokenTotalSupply() - bondingCurve.initialRealTokenReserves();

        uint256 feeBalanceAgentBefore = bondingCurve.getFeeBalance(feeToken, agentWallet);
        uint256 feeBalanceDevBefore = bondingCurve.getFeeBalance(feeToken, devWallet);

        // migrate liquidity
        expectEmit();
        emit LiquidityMigrated(
            token, expectedEthUsed, expectedTokenUsed, 33_021_520_764_495_386_879_234
        );
        vm.prank(agentWallet);
        bondingCurve.migrateLiquidity(token, 700);

        // check pool state
        pool = bondingCurve.getPool(token);
        assertEq(pool.realEthReserves, 0);
        assertEq(pool.realTokenReserves, 0);
        assertEq(pool.virtualEthReserves, 0);
        assertEq(pool.virtualTokenReserves, 0);
        assertEq(pool.complete, true);
        assertEq(pool.tokenTotalSupply, bondingCurve.tokenTotalSupply());
    }

    function testMigrateLiquidityFail() public {
        // case 1: not agent
        vm.expectRevert(NotAgent.selector);
        bondingCurve.migrateLiquidity(address(1), 1000);

        // case 2: invalid fee rate
        vm.prank(bondingCurve.agent());
        vm.expectRevert(InvalidFeeRate.selector);
        bondingCurve.migrateLiquidity(address(1), 1001);
    }

    function testClaimFeeSucceedsETH(uint256 ethAmount) public {
        ethAmount = bound(ethAmount, 1, 10 ether);

        address agentWallet = bondingCurve.agent();
        address devWallet = bondingCurve.dev();

        vm.prank(agentWallet);
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        // buy token
        vm.prank(alice);
        (uint256 fee,) = bondingCurve.buy{value: ethAmount}(token, 1);

        address feeToken = bondingCurve.ETH_ADDRESS();

        if (ethAmount >= 50) {
            assertGt(fee, 0);

            if (fee > 1) {
                expectEmit();
                emit FeeClaimed(feeToken, agentWallet, fee / 2);
                vm.prank(agentWallet);
                bondingCurve.claimFee(feeToken);
                assertEq(bondingCurve.getFeeBalance(feeToken, agentWallet), 0);
                assertEq(agentWallet.balance, fee / 2);
            }

            expectEmit();
            emit FeeClaimed(feeToken, devWallet, fee - (fee / 2));
            vm.prank(devWallet);
            bondingCurve.claimFee(feeToken);
            assertEq(bondingCurve.getFeeBalance(feeToken, devWallet), 0);
            assertEq(devWallet.balance, fee - (fee / 2));
        } else {
            assertEq(fee, 0);
        }
    }

    function testClaimFeeSucceedsToken(uint256 tokenAmount) public {
        tokenAmount = bound(tokenAmount, 1 ether, 700_000_000 ether);

        address agentWallet = bondingCurve.agent();
        address devWallet = bondingCurve.dev();

        vm.prank(agentWallet);
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", alice);

        // buy all tokens
        vm.startPrank(alice);
        (, uint256 tokenReturned) = bondingCurve.buy{value: 5.5 ether}(token, 1);
        vm.stopPrank();

        // sell tokens
        vm.prank(alice);
        IERC20(token).approve(address(bondingCurve), tokenReturned);
        vm.prank(alice);
        (uint256 feeByToken,) = bondingCurve.sell(token, tokenAmount, 1);

        // claim and check fee balance
        if (feeByToken > 1) {
            expectEmit();
            emit FeeClaimed(token, agentWallet, feeByToken / 2);
            vm.prank(agentWallet);
            bondingCurve.claimFee(token);
            assertEq(bondingCurve.getFeeBalance(token, agentWallet), 0);
            assertEq(IERC20(token).balanceOf(agentWallet), feeByToken / 2);
        }

        expectEmit();
        emit FeeClaimed(token, devWallet, feeByToken - (feeByToken / 2));
        vm.prank(devWallet);
        bondingCurve.claimFee(token);
        assertEq(bondingCurve.getFeeBalance(token, devWallet), 0);
        assertEq(IERC20(token).balanceOf(devWallet), feeByToken - (feeByToken / 2));
    }

    function testBuySellMigrationClaimFee() public {
        uint256 buyAmount = 0.06 ether;
        address agentWallet = bondingCurve.agent();
        address devWallet = bondingCurve.dev();

        vm.prank(bondingCurve.agent());
        address token = bondingCurve.deployToken(name, symbol, uint256(1), "", address(0xabcde));

        vm.startPrank(alice);
        IERC20(token).approve(address(bondingCurve), type(uint256).max);
        for (uint256 i = 1; i < 300; i++) {
            // buy token
            (, uint256 tokenReturned) = bondingCurve.buy{value: buyAmount}(token, 1);

            IBondingCurve.Pool memory pool = bondingCurve.getPool(token);
            uint256 marketCap = bondingCurve.tokenTotalSupply() * pool.virtualEthReserves
                / pool.virtualTokenReserves * 3660 / 1 ether;
            if (i == 1) {
                console.log("Iteration\tEthReserves\tTokenReserves\tMarketCap\tTokenSold");
            }
            console.log(
                i, pool.realEthReserves * 100 / 1 ether, pool.realTokenReserves / 1 ether, marketCap
            );
            if (pool.complete) {
                console.log(
                    "token price before migration: ",
                    pool.virtualEthReserves * 1 ether / pool.virtualTokenReserves
                );
                break;
            }

            // sell tokens for half of the returned
            bondingCurve.sell(token, tokenReturned * 2 / 3, 1);
        }
        vm.stopPrank();

        // migrate liquidity
        vm.prank(agentWallet);
        bondingCurve.migrateLiquidity(token, 700);

        // claim fee eth
        address feeETH = bondingCurve.ETH_ADDRESS();
        vm.prank(agentWallet);
        bondingCurve.claimFee(feeETH);
        vm.prank(devWallet);
        bondingCurve.claimFee(feeETH);

        address feeToken = token;
        // claim fee token
        vm.prank(agentWallet);
        bondingCurve.claimFee(feeToken);
        vm.prank(devWallet);
        bondingCurve.claimFee(feeToken);

        assertEq(
            IERC20(token).balanceOf(address(bondingCurve)), 0, "tokens of bondingCurve in the end"
        );

        vm.prank(alice);
        IERC20(token).transfer(bob, 1 ether);
        address[] memory sellPath = new address[](2);
        sellPath[0] = address(token);
        sellPath[1] = weth;
        vm.startPrank(bob);
        IERC20(token).approve(address(uniswapV2Router), 1 ether);
        // sell 1 token to uniswap
        IUniswapV2Router(uniswapV2Router)
            .swapExactTokensForETH(1 ether, 0, sellPath, bob, block.timestamp);
        console.log("token price after migration", bob.balance);
        vm.stopPrank();
    }

    function testClaimFeeFailNoFeeToClaim() public {
        address feeToken = bondingCurve.ETH_ADDRESS();
        vm.expectRevert(NoFeeToClaim.selector);
        bondingCurve.claimFee(feeToken);

        vm.expectRevert(NoFeeToClaim.selector);
        bondingCurve.claimFee(address(1));
    }

    function testSetParams() public {
        address owner = _cfg.initialOwner();

        expectEmit();
        emit ParamsSet(1, 2, 3, 4, 5);
        vm.prank(owner);
        bondingCurve.setParams(1, 2, 3, 4, 5);

        assertEq(bondingCurve.initialVirtualTokenReserves(), 1);
        assertEq(bondingCurve.initialVirtualEthReserves(), 2);
        assertEq(bondingCurve.initialRealTokenReserves(), 3);
        assertEq(bondingCurve.initialRealEthReserves(), 4);
        assertEq(bondingCurve.tokenTotalSupply(), 5);
    }

    function testSetParamsFailNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        bondingCurve.setParams(1, 2, 3, 4, 5);
    }

    function testSetupState() public view {
        // check global config
        assertGt(bondingCurve.initialVirtualTokenReserves(), bondingCurve.tokenTotalSupply());
        assertGe(bondingCurve.tokenTotalSupply(), bondingCurve.initialRealTokenReserves());
    }

    function _setup() internal {
        // read config from local.json
        string memory path = string.concat(vm.projectRoot(), "/deploy-config/", "local" ".json");
        _cfg = new DeployConfig(path);

        _preDeployWeth(weth);
        _preDeployUniswapV2(uniswapV2Factory, uniswapV2Router);

        // deploy impl
        BondingCurve impl =
            new BondingCurve(_cfg.uniswapV2Router(), _cfg.agentWallet(), _cfg.devWallet());

        // deploy proxy
        Proxy bondingCurveProxy = new Proxy(address(impl), _cfg.proxyAdminOwner(), "");
        bondingCurve = BondingCurve(address(bondingCurveProxy));

        // initialize
        bondingCurve.initialize(
            _cfg.initialVirtualTokenReserves(),
            _cfg.initialVirtualEthReserves(),
            _cfg.initialRealTokenReserves(),
            _cfg.initialRealEthReserves(),
            _cfg.tokenTotalSupply(),
            _cfg.initialOwner()
        );
    }
}
