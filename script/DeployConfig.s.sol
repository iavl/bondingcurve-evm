// SPDX-License-Identifier: MIT
// solhint-disable private-vars-leading-underscore,no-console
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title DeployConfig
/// @notice Represents the configuration required to deploy the system. It is expected
///         to read the file from JSON. A future improvement would be to have fallback
///         values if they are not defined in the JSON themselves.
contract DeployConfig is Script {
    string internal _json;

    address public proxyAdminOwner;
    address public initialOwner;
    uint256 public initialVirtualTokenReserves;
    uint256 public initialVirtualEthReserves;
    uint256 public initialRealTokenReserves;
    uint256 public initialRealEthReserves;
    uint256 public tokenTotalSupply;
    address public uniswapV2Router;
    address public agentWallet;
    address public devWallet;

    constructor(string memory _path) {
        console.log("DeployConfig: reading file %s", _path);
        try vm.readFile(_path) returns (string memory data) {
            _json = data;
        } catch {
            console.log(
                "Warning: unable to read config. Do not deploy unless you are not using config."
            );
            return;
        }

        proxyAdminOwner = stdJson.readAddress(_json, "$.proxyAdminOwner");
        initialOwner = stdJson.readAddress(_json, "$.initialOwner");
        initialVirtualTokenReserves = stdJson.readUint(_json, "$.initialVirtualTokenReserves");
        initialVirtualEthReserves = stdJson.readUint(_json, "$.initialVirtualEthReserves");
        initialRealTokenReserves = stdJson.readUint(_json, "$.initialRealTokenReserves");
        initialRealEthReserves = stdJson.readUint(_json, "$.initialRealEthReserves");
        tokenTotalSupply = stdJson.readUint(_json, "$.tokenTotalSupply");
        uniswapV2Router = stdJson.readAddress(_json, "$.uniswapV2Router");
        agentWallet = stdJson.readAddress(_json, "$.agentWallet");
        devWallet = stdJson.readAddress(_json, "$.devWallet");
    }
}
