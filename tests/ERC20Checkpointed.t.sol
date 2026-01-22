// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ERC20Checkpointed} from "../contracts/ERC20Checkpointed.sol";
import {IERC20Checkpointed} from "../contracts/interfaces/IERC20Checkpointed.sol";

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

contract ERC20CheckpointedTest is Test {
    MockERC20Checkpointed token;
    address alice = vm.randomAddress();
    address bob = vm.randomAddress();

    function setUp() public {
        token = new MockERC20Checkpointed("Mock", "MOCK");
    }

    function test_InitialStateIsZero() public {
        assertEq(token.totalSupply(), 0, "totalSupply should be 0 initially");
        assertEq(token.totalSupplyAt(0), 0, "totalSupplyAt(0) should be 0 when no checkpoints");
        assertEq(token.balanceOf(alice), 0, "alice balance should be 0 initially");
        assertEq(token.balanceOfAt(alice, 0), 0, "alice balanceAt(0) should be 0 when no checkpoints");
    }

    function test_CheckpointingMintTransferBurn() public {
        // checkpoint 1: mint 100 to Alice
        token.mint(alice, 100);
        assertEq(token.totalSupply(), 100);
        assertEq(token.totalSupplyAt(1), 100, "supply at cp1 should reflect mint");
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOfAt(alice, 1), 100, "alice at cp1 should be 100");
        assertEq(token.balanceOfAt(bob, 1), 0, "bob at cp1 should be 0");

        // checkpoint 2: transfer 40 from Alice to Bob
        vm.prank(alice);
        token.transfer(bob, 40);
        assertEq(token.totalSupply(), 100, "supply unchanged after transfer");
        assertEq(token.totalSupplyAt(2), 100, "supply at cp2 should be 100");
        assertEq(token.balanceOf(alice), 60, "alice latest should be 60");
        assertEq(token.balanceOf(bob), 40, "bob latest should be 40");
        assertEq(token.balanceOfAt(alice, 2), 60, "alice at cp2 should be 60");
        assertEq(token.balanceOfAt(bob, 2), 40, "bob at cp2 should be 40");

        // checkpoint 3: burn 10 from Bob
        token.burn(bob, 10);
        assertEq(token.totalSupply(), 90, "supply should reduce after burn");
        assertEq(token.totalSupplyAt(3), 90, "supply at cp3 should be 90");
        assertEq(token.balanceOf(bob), 30, "bob latest should be 30");
        assertEq(token.balanceOfAt(bob, 3), 30, "bob at cp3 should be 30");

        // Historical queries remain consistent
        assertEq(token.balanceOfAt(alice, 0), 0, "alice at cp0 unchanged");
        assertEq(token.balanceOfAt(alice, 1), 100, "alice at cp1 unchanged");
        assertEq(token.balanceOfAt(alice, 2), 60, "alice at cp2 is still 60");
        assertEq(token.balanceOfAt(alice, 3), 60, "alice at cp2 is still 60");
        assertEq(token.balanceOfAt(bob, 0), 0, "bob at cp0 unchanged");
        assertEq(token.balanceOfAt(bob, 1), 0, "bob at cp1 unchanged");
        assertEq(token.balanceOfAt(bob, 2), 40, "bob at cp2 unchanged");
        assertEq(token.balanceOfAt(bob, 3), 30, "bob at cp3 unchanged");

        // Querying a future checkpoint should revert
        vm.expectRevert(abi.encodeWithSelector(IERC20Checkpointed.ERC20FutureCheckpoint.selector, 999, 3));
        token.totalSupplyAt(999);

        vm.expectRevert(abi.encodeWithSelector(IERC20Checkpointed.ERC20FutureCheckpoint.selector, 999, 3));
        token.balanceOfAt(alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IERC20Checkpointed.ERC20FutureCheckpoint.selector, 999, 3));
        token.balanceOfAt(bob, 999);
    }
}

/**
 * Basic tests to ensure ERC20Checkpointed have the same behaviour as OZ's ERC20
 */
contract ERC20Test is Test {
    MockERC20Checkpointed ctk; // checkpointed token
    MockOZERC20 oz; // reference OZ token

    address deployer = address(this);
    address alice = vm.randomAddress();
    address bob = vm.randomAddress();
    address carol = vm.randomAddress();

    function setUp() public {
        ctk = new MockERC20Checkpointed("MockToken", "MCK");
        oz = new MockOZERC20("MockToken", "MCK");

        // mint initial balances to alice
        ctk.mint(alice, 1_000 ether);
        oz.mint(alice, 1_000 ether);
    }

    function test_NameSymbolDecimals() public {
        assertEq(ctk.name(), oz.name(), "name should match");
        assertEq(ctk.symbol(), oz.symbol(), "symbol should match");
        assertEq(ctk.decimals(), oz.decimals(), "decimals should match");
    }

    function test_BalancesAndSupplyAfterMint() public {
        assertEq(ctk.totalSupply(), oz.totalSupply(), "totalSupply after mint should match");
        assertEq(ctk.balanceOf(alice), oz.balanceOf(alice), "alice balance after mint should match");
        assertEq(ctk.balanceOf(bob), oz.balanceOf(bob), "bob balance after mint should match");
    }

    function test_Transfer() public {
        // alice transfers to bob
        vm.startPrank(alice);
        bool s1 = ctk.transfer(bob, 200 ether);
        bool s2 = oz.transfer(bob, 200 ether);
        vm.stopPrank();

        assertTrue(s1 && s2, "transfer should succeed on both");
        assertEq(ctk.totalSupply(), oz.totalSupply(), "supply unchanged");
        assertEq(ctk.balanceOf(alice), oz.balanceOf(alice), "alice balance equal after transfer");
        assertEq(ctk.balanceOf(bob), oz.balanceOf(bob), "bob balance equal after transfer");

        vm.roll(block.number + 10);

        // bob transfer to carol
        vm.startPrank(bob);
        bool t1 = ctk.transfer(carol, 50 ether);
        bool t2 = oz.transfer(carol, 50 ether);
        vm.stopPrank();

        assertTrue(t1 && t2, "transfer should succeed on both");
        assertEq(ctk.totalSupply(), oz.totalSupply(), "supply unchanged after bob to carol");
        assertEq(ctk.balanceOf(bob), oz.balanceOf(bob), "bob balance equal after transfer to carol");
        assertEq(ctk.balanceOf(carol), oz.balanceOf(carol), "carol balance equal after receiving from bob");
    }

    function test_ApproveAndTransferFrom() public {
        // alice approves bob
        vm.startPrank(alice);
        bool a1 = ctk.approve(bob, 300 ether);
        bool a2 = oz.approve(bob, 300 ether);
        vm.stopPrank();
        assertTrue(a1 && a2, "approve ok");
        assertEq(ctk.allowance(alice, bob), oz.allowance(alice, bob), "allowance match");

        // bob spends half to carol
        vm.startPrank(bob);
        bool t1a = ctk.transferFrom(alice, carol, 150 ether);
        bool t2a = oz.transferFrom(alice, carol, 150 ether);
        // spend the rest
        bool t1b = ctk.transferFrom(alice, carol, 150 ether);
        bool t2b = oz.transferFrom(alice, carol, 150 ether);
        vm.stopPrank();
        assertTrue(t1a && t2a && t1b && t2b, "transferFrom ok");

        assertEq(ctk.allowance(alice, bob), oz.allowance(alice, bob), "allowance consumed equally");
        assertEq(ctk.balanceOf(alice), oz.balanceOf(alice), "alice balance equal after transferFrom");
        assertEq(ctk.balanceOf(carol), oz.balanceOf(carol), "carol balance equal after transferFrom");
        assertEq(ctk.totalSupply(), oz.totalSupply(), "supply equal after transferFrom");
    }

    function test_Reverts() public {
        // transfer more than balance
        vm.startPrank(bob); // bob has 0 initially
        vm.expectRevert();
        ctk.transfer(alice, 1);
        vm.expectRevert();
        oz.transfer(alice, 1);
        vm.stopPrank();

        // transfer to zero address
        vm.startPrank(alice);
        vm.expectRevert();
        ctk.transfer(address(0), 1);
        vm.expectRevert();
        oz.transfer(address(0), 1);
        vm.stopPrank();

        // transferFrom without approval
        vm.prank(bob);
        vm.expectRevert();
        ctk.transferFrom(alice, bob, 1);
        vm.prank(bob);
        vm.expectRevert();
        oz.transferFrom(alice, bob, 1);
    }

    function test_MintAndBurn() public {
        // mint to bob
        ctk.mint(bob, 500 ether);
        oz.mint(bob, 500 ether);
        assertEq(ctk.balanceOf(bob), oz.balanceOf(bob));
        assertEq(ctk.totalSupply(), oz.totalSupply());

        // burn from alice partially
        ctk.burn(alice, 100 ether);
        oz.burn(alice, 100 ether);
        assertEq(ctk.balanceOf(alice), oz.balanceOf(alice));
        assertEq(ctk.totalSupply(), oz.totalSupply());
    }
}
