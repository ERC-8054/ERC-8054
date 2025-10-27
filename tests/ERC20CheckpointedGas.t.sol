// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ERC20Checkpointed} from "../contracts/ERC20Checkpointed.sol";

// Minimal mock to expose mint for setup
contract MockERC20Checkpointed is ERC20Checkpointed {
    constructor(string memory name_, string memory symbol_) ERC20Checkpointed(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockERC20OZ is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

/**
 * Run gas test with --isolate to get consistent measurements.
 */
contract ERC20CheckpointedGasTest is Test {
    MockERC20Checkpointed token;
    MockERC20OZ token2;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new MockERC20Checkpointed("Mock", "MOCK");
        token.mint(alice, 1_000 ether);

        token2 = new MockERC20OZ("Mock2", "MOCK2");
        token2.mint(alice, 1_000 ether);
    }

    // Simple gas test for transfer
    function test_transfer_gas_cold() public {
        uint256 gasUsed = _transferToken(alice, bob, 1 ether);

        // Log the gas used so it appears in test output / CI logs
        console.log("Gas used: transfer_cold", gasUsed);
    }

    // Simple gas test for transfer on standard ERC20 for comparison
    function test_transfer_gas_erc20_cold() public {
        uint256 gasUsed = _transferToken2(alice, bob, 1 ether);

        // Log the gas used so it appears in test output / CI logs
        console.log("Gas used: transfer_erc20_cold", gasUsed);
    }

    function test_transfer_gas_warm() public {
        // warm up
        vm.startPrank(alice);
        token.transfer(bob, 1 ether);
        vm.stopPrank();

        uint256 gasUsed = _transferToken(alice, bob, 1 ether);

        // Log the gas used so it appears in test output / CI logs
        console.log("Gas used: transfer_warm", gasUsed);
    }

    function test_transfer_gas_erc20_warm() public {
        // warm up
        vm.startPrank(alice);
        token2.transfer(bob, 1 ether);
        vm.stopPrank();

        uint256 gasUsed = _transferToken2(alice, bob, 1 ether);

        // Log the gas used so it appears in test output / CI logs
        console.log("Gas used: transfer_erc20_warm", gasUsed);
    }

    function _transferToken(address from, address to, uint256 amount) internal returns (uint256 gasUsed) {
        vm.startPrank(from);
        uint256 gasBefore = gasleft();
        token.transfer(to, amount);
        uint256 gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        vm.stopPrank();
    }

    function _transferToken2(address from, address to, uint256 amount) internal returns (uint256 gasUsed) {
        vm.startPrank(from);
        uint256 gasBefore = gasleft();
        token2.transfer(to, amount);
        uint256 gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        vm.stopPrank();
    }
}
