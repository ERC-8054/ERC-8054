// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ERC20Checkpointed} from "../contracts/ERC20Checkpointed.sol";
import {ERC20Forked} from "../contracts/ERC20Forked.sol";


contract MockERC20Checkpointed is ERC20Checkpointed {
    constructor(string memory name_, string memory symbol_) ERC20Checkpointed(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}

contract MockOZERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}

contract MockERC20Forked is ERC20Forked {
    constructor(string memory name_, string memory symbol_, uint48 checkpointedNonce_, address checkpointedToken_)
        ERC20Forked(name_, symbol_, checkpointedNonce_, checkpointedToken_)
    {}

    function mint(address to, uint256 amount) public {
        _update(address(0), to, amount);
    }

    function burn(address from, uint256 amount) public {
        _update(from, address(0), amount);
    }
}

contract ERC20ForkedGas is Test {
    MockERC20Checkpointed sourceToken; // checkpointed source token
    MockERC20Forked token;
    MockOZERC20 token2;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        vm.roll(10000);

        sourceToken = new MockERC20Checkpointed("Source", "SRC");
        sourceToken.mint(alice, 1_000 ether);
        sourceToken.mint(bob, 1_000 ether);

        vm.roll(block.number + 1);

        token = new MockERC20Forked("Mock", "MOCK", sourceToken.checkpointNonce(), address(sourceToken));

        token2 = new MockOZERC20("Mock2", "MOCK2");
        token2.mint(alice, 1_000 ether);
        token2.mint(bob, 1_000 ether);
    }

    // Simple gas test for transfer
    function test_transfer_gas() public {
        vm.startPrank(alice);
        uint256 gasBefore = gasleft();
        token.transfer(bob, 1 ether);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        vm.stopPrank();

        // Log the gas used so it appears in test output / CI logs
        console.log("Gas used: transfer", gasUsed);
    }

    // Simple gas test for transfer on standard ERC20 for comparison
    function test_transfer_gas_erc20() public {
        vm.startPrank(alice);
        uint256 gasBefore = gasleft();
        token2.transfer(bob, 1 ether);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        vm.stopPrank();

        // Log the gas used so it appears in test output / CI logs
        console.log("Gas used: transfer ERC20", gasUsed);
    }
}
