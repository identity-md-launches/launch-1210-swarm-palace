// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPALACEToken} from "../src/SPALACEToken.sol";

interface DeployVm {
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Standalone simulation helper. Production launch uses the network factory.
/// @dev Reads no keys. EXPECTED_CHAIN_ID=0 explicitly permits a local dry run.
contract Deploy {
    DeployVm private constant vm = DeployVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external returns (SPALACEToken token) {
        uint256 expectedChainId = vm.envOr("EXPECTED_CHAIN_ID", uint256(1));
        require(expectedChainId == 0 || block.chainid == expectedChainId, "unexpected chain");
        vm.startBroadcast();
        token = new SPALACEToken();
        vm.stopBroadcast();
    }
}
