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

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract ERC20TransferGasTest is Test {
    MockERC20Checkpointed token;
    MockERC20 token2;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new MockERC20Checkpointed("Mock", "MOCK");
        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);

        token2 = new MockERC20("Mock2", "MOCK2");
        token2.mint(alice, 1_000 ether);
        token2.mint(bob, 1_000 ether);
    }

    // Simple gas test for transfer
    function test_transfer_gas() public {
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        token.transfer(bob, 1 ether);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Log the gas used so it appears in test output / CI logs
        console.log("Gas used: transfer", gasUsed);

        // Optional loose upper bound to catch accidental regressions while avoiding flakiness
        // Adjust threshold if needed based on local runs. This is intentionally generous.
        assertLt(gasUsed, 150_000, "transfer gas should be below threshold");
    }

    // Simple gas test for transfer on standard ERC20 for comparison
    function test_transfer_gas_erc20() public {
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        token2.transfer(bob, 1 ether);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Log the gas used so it appears in test output / CI logs
        console.log("Gas used: transfer ERC20", gasUsed);

        // Optional loose upper bound to catch accidental regressions while avoiding flakiness
        // Adjust threshold if needed based on local runs. This is intentionally generous.
        assertLt(gasUsed, 60_000, "transfer ERC20 gas should be below threshold");
    }
}
