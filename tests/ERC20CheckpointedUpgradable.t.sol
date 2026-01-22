// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ERC20CheckpointedUpgradable} from "../contracts/ERC20CheckpointedUpgradable.sol";
import {IERC20Checkpointed} from "../contracts/interfaces/IERC20Checkpointed.sol";

contract MockERC20CheckpointedUpgradable is ERC20CheckpointedUpgradable {
    function initialize(string memory name_, string memory symbol_) public initializer {
        __ERC20_init(name_, symbol_);
    }

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

contract ERC20CheckpointedUpgradableTest is Test {
    MockERC20CheckpointedUpgradable token;

    address alice = vm.randomAddress();
    address bob = vm.randomAddress();

    function setUp() public {
        // deploy proxy instance of the checkpointed token
        MockERC20CheckpointedUpgradable impl = new MockERC20CheckpointedUpgradable();
        bytes memory data =
            abi.encodeWithSelector(MockERC20CheckpointedUpgradable.initialize.selector, "MockToken", "MCK");
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        token = MockERC20CheckpointedUpgradable(address(proxy));
    }

    function test_InitialStateIsZero() public {
        assertEq(token.totalSupply(), 0 ether, "totalSupply should be zero");
        assertEq(token.balanceOf(alice), 0 ether, "alice balance should zero");
        assertEq(token.totalSupplyAt(0), 0, "totalSupplyAt(0) should be 0 when no checkpoints");
        assertEq(token.balanceOfAt(alice, 0), 0, "alice balanceAt(0) should be 0 when no checkpoints");
    }

    function test_CheckpointingMintTransferBurnAndNonce() public {
        // checkpoint 1: mint 100 to Alice
        token.mint(alice, 100);
        assertEq(token.checkpointNonce(), 1, "nonce cp1");
        assertEq(token.totalSupply(), 100);
        assertEq(token.totalSupplyAt(1), 100, "supply at cp1 should reflect mint");
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOfAt(alice, 1), 100, "alice at cp1 should be 100");
        assertEq(token.balanceOfAt(bob, 1), 0, "bob at cp1 should be 0");

        // checkpoint 2: transfer 40 from Alice to Bob
        vm.prank(alice);
        token.transfer(bob, 40);
        assertEq(token.checkpointNonce(), 2, "nonce cp2");
        assertEq(token.totalSupply(), 100, "supply unchanged after transfer");
        assertEq(token.totalSupplyAt(2), 100, "supply at cp2 should be 100");
        assertEq(token.balanceOf(alice), 60, "alice latest should be 60");
        assertEq(token.balanceOf(bob), 40, "bob latest should be 40");
        assertEq(token.balanceOfAt(alice, 2), 60, "alice at cp2 should be 60");
        assertEq(token.balanceOfAt(bob, 2), 40, "bob at cp2 should be 40");

        // checkpoint 3: burn 10 from Bob
        token.burn(bob, 10);
        assertEq(token.checkpointNonce(), 3, "nonce cp3");
        assertEq(token.totalSupply(), 90, "supply should reduce after burn");
        assertEq(token.totalSupplyAt(3), 90, "supply at cp3 should be 90");
        assertEq(token.balanceOf(bob), 30, "bob latest should be 30");
        assertEq(token.balanceOfAt(bob, 3), 30, "bob at cp3 should be 30");

        // Historical queries remain consistent
        assertEq(token.balanceOfAt(alice, 0), 0, "alice at cp0 unchanged");
        assertEq(token.balanceOfAt(alice, 1), 100, "alice at cp1 unchanged");
        assertEq(token.balanceOfAt(alice, 2), 60, "alice at cp2 is still 60");
        assertEq(token.balanceOfAt(alice, 3), 60, "alice at cp3 is still 60");
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

contract ERC20Test is Test {
    MockERC20CheckpointedUpgradable public token; // checkpointed token via proxy
    MockOZERC20 public tokenOZ; // reference OZ token

    address alice = vm.randomAddress();
    address bob = vm.randomAddress();
    address carol = vm.randomAddress();

    function setUp() public {
        // deploy proxy instance of the checkpointed token
        MockERC20CheckpointedUpgradable impl = new MockERC20CheckpointedUpgradable();
        bytes memory data =
            abi.encodeWithSelector(MockERC20CheckpointedUpgradable.initialize.selector, "MockToken", "MCK");
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        token = MockERC20CheckpointedUpgradable(address(proxy));

        // deploy reference OZ ERC20
        tokenOZ = new MockOZERC20("MockToken", "MCK");

        // mint initial balances to alice
        token.mint(alice, 1_000 ether);
        tokenOZ.mint(alice, 1_000 ether);
    }

    function test_NameSymbolDecimals() public {
        assertEq(token.name(), tokenOZ.name(), "name should match");
        assertEq(token.symbol(), tokenOZ.symbol(), "symbol should match");
        assertEq(token.decimals(), tokenOZ.decimals(), "decimals should match");
    }

    function test_BalancesAndSupplyAfterMint() public {
        assertEq(token.totalSupply(), tokenOZ.totalSupply(), "totalSupply after mint should match");
        assertEq(token.balanceOf(alice), tokenOZ.balanceOf(alice), "alice balance after mint should match");
        assertEq(token.balanceOf(bob), tokenOZ.balanceOf(bob), "bob balance after mint should match");
    }

    function test_Transfer() public {
        // alice transfers to bob
        vm.startPrank(alice);
        bool s1 = token.transfer(bob, 200 ether);
        bool s2 = tokenOZ.transfer(bob, 200 ether);
        vm.stopPrank();

        assertTrue(s1 && s2, "transfer should succeed on both");
        assertEq(token.totalSupply(), tokenOZ.totalSupply(), "supply unchanged");
        assertEq(token.balanceOf(alice), tokenOZ.balanceOf(alice), "alice balance equal after transfer");
        assertEq(token.balanceOf(bob), tokenOZ.balanceOf(bob), "bob balance equal after transfer");

        vm.roll(block.number + 10);

        // bob transfer to carol
        vm.startPrank(bob);
        bool t1 = token.transfer(carol, 50 ether);
        bool t2 = tokenOZ.transfer(carol, 50 ether);
        vm.stopPrank();

        assertTrue(t1 && t2, "transfer should succeed on both");
        assertEq(token.totalSupply(), tokenOZ.totalSupply(), "supply unchanged after bob to carol");
        assertEq(token.balanceOf(bob), tokenOZ.balanceOf(bob), "bob balance equal after transfer to carol");
        assertEq(token.balanceOf(carol), tokenOZ.balanceOf(carol), "carol balance equal after receiving from bob");
    }

    function test_ApproveAndTransferFrom() public {
        // alice approves bob
        vm.startPrank(alice);
        bool a1 = token.approve(bob, 300 ether);
        bool a2 = tokenOZ.approve(bob, 300 ether);
        vm.stopPrank();
        assertTrue(a1 && a2, "approve ok");
        assertEq(token.allowance(alice, bob), tokenOZ.allowance(alice, bob), "allowance match");

        // bob spends half to carol
        vm.startPrank(bob);
        bool t1a = token.transferFrom(alice, carol, 150 ether);
        bool t2a = tokenOZ.transferFrom(alice, carol, 150 ether);
        // spend the rest
        bool t1b = token.transferFrom(alice, carol, 150 ether);
        bool t2b = tokenOZ.transferFrom(alice, carol, 150 ether);
        vm.stopPrank();
        assertTrue(t1a && t2a && t1b && t2b, "transferFrom ok");

        assertEq(token.allowance(alice, bob), tokenOZ.allowance(alice, bob), "allowance consumed equally");
        assertEq(token.balanceOf(alice), tokenOZ.balanceOf(alice), "alice balance equal after transferFrom");
        assertEq(token.balanceOf(carol), tokenOZ.balanceOf(carol), "carol balance equal after transferFrom");
        assertEq(token.totalSupply(), tokenOZ.totalSupply(), "supply equal after transferFrom");
    }

    function test_Reverts() public {
        // transfer more than balance
        vm.startPrank(bob); // bob has 0 initially
        vm.expectRevert();
        token.transfer(alice, 1);
        vm.expectRevert();
        tokenOZ.transfer(alice, 1);
        vm.stopPrank();

        // transfer to zero address
        vm.startPrank(alice);
        vm.expectRevert();
        token.transfer(address(0), 1);
        vm.expectRevert();
        tokenOZ.transfer(address(0), 1);
        vm.stopPrank();

        // transferFrom without approval
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, bob, 1);
        vm.prank(bob);
        vm.expectRevert();
        tokenOZ.transferFrom(alice, bob, 1);
    }

    function test_MintAndBurn() public {
        // mint to bob
        token.mint(bob, 500 ether);
        tokenOZ.mint(bob, 500 ether);
        assertEq(token.balanceOf(bob), tokenOZ.balanceOf(bob));
        assertEq(token.totalSupply(), tokenOZ.totalSupply());

        // burn from alice partially
        token.burn(alice, 100 ether);
        tokenOZ.burn(alice, 100 ether);
        assertEq(token.balanceOf(alice), tokenOZ.balanceOf(alice));
        assertEq(token.totalSupply(), tokenOZ.totalSupply());
    }
}
