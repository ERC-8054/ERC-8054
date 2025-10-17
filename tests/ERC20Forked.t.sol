// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
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
    constructor(string memory name_, string memory symbol_, uint32 checkpointedNonce_, address checkpointedToken_)
        ERC20Forked(name_, symbol_, checkpointedNonce_, checkpointedToken_) {}

    function mint(address to, uint256 amount) public {
        _update(address(0), to, amount);
    }

    function burn(address from, uint256 amount) public {
        _update(from, address(0), amount);
    }
}

/**
 * Basic tests to ensure ERC20Forked has standard ERC20 behaviour given a checkpointed source.
 */
contract ERC20ForkedTest is Test {
    MockERC20Checkpointed source; // checkpointed source token
    MockERC20Forked frk; // forked token under test
    MockOZERC20 oz; // reference OZ token

    address deployer = address(this);
    address alice = vm.randomAddress();
    address bob = vm.randomAddress();
    address carol = vm.randomAddress();

    uint32 forkNonce;

    function setUp() public {
        // 1) Prepare source checkpointed token state
        source = new MockERC20Checkpointed("Source", "SRC");
        // mint initial to alice
        source.mint(alice, 1_000 ether); // cp1
        // transfer some to bob to have multiple holders
        vm.prank(alice);
        source.transfer(bob, 200 ether); // cp2
        // leave some movements so that balances differ
        source.burn(alice, 50 ether); // cp3

        // choose fork nonce at current checkpoint
        forkNonce = uint32(source.checkpointNonce());

        // 2) Deploy forked token at that nonce reading balances/supply from source
        frk = new MockERC20Forked("Forked", "FRK", forkNonce, address(source));

        // 3) Deploy OZ reference token with the same initial distribution as at the fork nonce
        oz = new MockOZERC20("Forked", "FRK");
        // match balances for the relevant accounts (alice, bob). others default to zero
        oz.mint(alice, source.balanceOfAt(alice, forkNonce));
        oz.mint(bob, source.balanceOfAt(bob, forkNonce));
        // Ensure totals match the source snapshot
        uint256 expectedSupply = source.totalSupplyAt(forkNonce);
        uint256 mintedSupply = oz.totalSupply();
        assertEq(mintedSupply, expectedSupply, "initial supply should match source at fork nonce");
    }

    function test_MetadataAndInitialBalances() public {
        // Name/symbol/decimals should match
        assertEq(frk.name(), oz.name(), "name should match");
        assertEq(frk.symbol(), oz.symbol(), "symbol should match");
        assertEq(frk.decimals(), source.decimals(), "forked uses source decimals");

        // Balances and total supply at fork moment should match OZ reference initialization
        assertEq(frk.totalSupply(), oz.totalSupply(), "initial totalSupply should match");
        assertEq(frk.balanceOf(alice), oz.balanceOf(alice), "alice initial balance should match");
        assertEq(frk.balanceOf(bob), oz.balanceOf(bob), "bob initial balance should match");
        assertEq(frk.balanceOf(carol), oz.balanceOf(carol), "carol initial balance should match (0)");
    }

    function test_Transfer() public {
        // alice transfers to bob
        vm.startPrank(alice);
        bool t1 = frk.transfer(bob, 100 ether);
        bool t2 = oz.transfer(bob, 100 ether);
        vm.stopPrank();
        assertTrue(t1 && t2, "transfer should succeed on both");
        assertEq(frk.totalSupply(), oz.totalSupply(), "supply unchanged after transfer");
        assertEq(frk.balanceOf(alice), oz.balanceOf(alice), "alice balance equal after transfer");
        assertEq(frk.balanceOf(bob), oz.balanceOf(bob), "bob balance equal after transfer");

        // bob transfers to carol
        vm.startPrank(bob);
        t1 = frk.transfer(carol, 25 ether);
        t2 = oz.transfer(carol, 25 ether);
        vm.stopPrank();
        assertTrue(t1 && t2, "transfer should succeed on both");
        assertEq(frk.totalSupply(), oz.totalSupply(), "supply unchanged after bob to carol");
        assertEq(frk.balanceOf(bob), oz.balanceOf(bob), "bob balance equal after transfer to carol");
        assertEq(frk.balanceOf(carol), oz.balanceOf(carol), "carol balance equal after receiving from bob");
    }

    function test_ApproveAndTransferFrom() public {
        // alice approves bob
        vm.startPrank(alice);
        bool a1 = frk.approve(bob, 300 ether);
        bool a2 = oz.approve(bob, 300 ether);
        vm.stopPrank();
        assertTrue(a1 && a2, "approve ok");
        assertEq(frk.allowance(alice, bob), oz.allowance(alice, bob), "allowance match");

        // bob spends half to carol
        vm.startPrank(bob);
        bool t1a = frk.transferFrom(alice, carol, 150 ether);
        bool t2a = oz.transferFrom(alice, carol, 150 ether);
        // spend the rest
        bool t1b = frk.transferFrom(alice, carol, 150 ether);
        bool t2b = oz.transferFrom(alice, carol, 150 ether);
        vm.stopPrank();
        assertTrue(t1a && t2a && t1b && t2b, "transferFrom ok");

        assertEq(frk.allowance(alice, bob), oz.allowance(alice, bob), "allowance consumed equally");
        assertEq(frk.balanceOf(alice), oz.balanceOf(alice), "alice balance equal after transferFrom");
        assertEq(frk.balanceOf(carol), oz.balanceOf(carol), "carol balance equal after transferFrom");
        assertEq(frk.totalSupply(), oz.totalSupply(), "supply equal after transferFrom");
    }

    function test_Reverts() public {
        // transfer more than balance
        vm.startPrank(bob); // bob has limited balance from snapshot
        vm.expectRevert();
        frk.transfer(alice, type(uint256).max);
        vm.expectRevert();
        oz.transfer(alice, type(uint256).max);
        vm.stopPrank();

        // transfer to zero address
        vm.startPrank(alice);
        vm.expectRevert();
        frk.transfer(address(0), 1);
        vm.expectRevert();
        oz.transfer(address(0), 1);
        vm.stopPrank();

        // transferFrom without approval
        vm.prank(bob);
        vm.expectRevert();
        frk.transferFrom(alice, bob, 1);
        vm.prank(bob);
        vm.expectRevert();
        oz.transferFrom(alice, bob, 1);
    }

    function test_MintAndBurn() public {
        // mint to bob
        frk.mint(bob, 500 ether);
        oz.mint(bob, 500 ether);
        assertEq(frk.balanceOf(bob), oz.balanceOf(bob));
        assertEq(frk.totalSupply(), oz.totalSupply());

        // burn from alice partially
        frk.burn(alice, 100 ether);
        oz.burn(alice, 100 ether);
        assertEq(frk.balanceOf(alice), oz.balanceOf(alice));
        assertEq(frk.totalSupply(), oz.totalSupply());
    }

    function test_SourceStateChangesPostForkDoNotAffectForkedToken() public {
        // capture initial forked snapshot values
        uint256 frkSupply0 = frk.totalSupply();
        uint256 frkAlice0 = frk.balanceOf(alice);
        uint256 frkBob0 = frk.balanceOf(bob);
        uint256 frkCarol0 = frk.balanceOf(carol);

        // mutate the SOURCE token AFTER the fork nonce
        address dave = vm.randomAddress();
        // mint to alice
        source.mint(alice, 777);
        // transfer from bob to carol
        vm.prank(bob);
        source.transfer(carol, 33);
        // burn from alice
        source.burn(alice, 111);
        // mint to a new holder who did not exist at snapshot
        source.mint(dave, 555);

        // forked token must remain unaffected (isolated from source post-fork changes)
        assertEq(frk.totalSupply(), frkSupply0, "forked totalSupply must be unchanged after source changes");
        assertEq(frk.balanceOf(alice), frkAlice0, "alice forked balance unchanged");
        assertEq(frk.balanceOf(bob), frkBob0, "bob forked balance unchanged");
        assertEq(frk.balanceOf(carol), frkCarol0, "carol forked balance unchanged");
        assertEq(frk.balanceOf(dave), 0, "new holders after fork have 0 balance in fork");

        // sanity: prove that the source token state did change as expected
        assertEq(source.totalSupply(), frkSupply0 + 777 - 111 + 555, "source supply reflects post-fork mints/burns");
        assertEq(source.balanceOf(alice), frkAlice0 + 777 - 111, "source alice changed post-fork");
        assertEq(source.balanceOf(bob), frkBob0 - 33, "source bob changed post-fork");
        assertEq(source.balanceOf(carol), frkCarol0 + 33, "source carol changed post-fork");
        assertEq(source.balanceOf(dave), 555, "source dave minted post-fork");
    }
}
