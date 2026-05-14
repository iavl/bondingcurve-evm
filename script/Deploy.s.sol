// SPDX-License-Identifier: MIT
// solhint-disable no-console,ordering,custom-errors
pragma solidity 0.8.26;

import {BondingCurve} from "../src/BondingCurve.sol";
import {DeployConfig} from "./DeployConfig.s.sol";
import {Deployer} from "./Deployer.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {console} from "forge-std/console.sol";

contract Deploy is Deployer {
    DeployConfig internal _cfg;

    /// @notice Modifier that wraps a function in broadcasting.
    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    /// @notice The name of the script, used to ensure the right deploy artifacts
    ///         are used.
    function name() public pure override returns (string memory name_) {
        name_ = "Deploy";
    }

    function setUp() public override {
        super.setUp();
        string memory path =
            string.concat(vm.projectRoot(), "/deploy-config/", deploymentContext, ".json");
        _cfg = new DeployConfig(path);

        console.log("Deploying from %s", deployScript);
        console.log("Deployment context: %s", deploymentContext);
    }

    /* solhint-disable comprehensive-interface */
    function run() external {
        deployImplementations();

        deployProxies();

        initialize();
    }

    /// @notice Deploy all of the proxies
    function deployProxies() public broadcast {
        deployProxy("BondingCurve");
    }

    /// @notice Deploy all of the logic contracts
    function deployImplementations() public broadcast {
        deployBondingCurve();
    }

    /// @notice Initialize all of the proxies
    function initialize() public broadcast {
        initializeBondingCurve();
    }

    function deployProxy(string memory name_) public returns (address addr_) {
        console.log("Deploying BondingCurveProxy");
        address logic = mustGetAddress(_stripSemver(name_));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy({
            _logic: logic, initialOwner: _cfg.proxyAdminOwner(), _data: ""
        });

        string memory proxyName = string.concat(name_, "Proxy");
        save(proxyName, address(proxy));
        console.log("%s deployed at %s", proxyName, address(proxy));

        addr_ = address(proxy);
    }

    function deployBondingCurve() public returns (address addr) {
        console.log("Deploying BondingCurve.sol");
        BondingCurve bondingCurve =
            new BondingCurve(_cfg.uniswapV2Router(), _cfg.agentWallet(), _cfg.devWallet());

        save("BondingCurve", address(bondingCurve));
        console.log("BondingCurve deployed at %s", address(bondingCurve));
        addr = address(bondingCurve);
    }

    function initializeBondingCurve() public {
        console.log("Initializing BondingCurve");
        BondingCurve bondingCurveProxy = BondingCurve(mustGetAddress("BondingCurveProxy"));

        bondingCurveProxy.initialize(
            _cfg.initialVirtualTokenReserves(),
            _cfg.initialVirtualEthReserves(),
            _cfg.initialRealTokenReserves(),
            _cfg.initialRealEthReserves(),
            _cfg.tokenTotalSupply(),
            _cfg.initialOwner()
        );
    }
}
