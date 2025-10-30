// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ERC4626Checkpointed} from "../../contracts/extensions/ERC4626Checkpointed.sol";

contract MockAsset18 is ERC20 {
    constructor() ERC20("MockAsset18", "MA18") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockAsset6 is ERC20 {
    constructor() ERC20("MockAsset6", "MA6") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockVault is ERC4626Checkpointed {
    function initialize(address asset_, string memory name_, string memory symbol_) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC4626_init(IERC20(asset_));
    }
}

contract ERC4626CheckpointedTest is Test {
    MockAsset18 asset18;
    MockAsset6 asset6;
    MockVault vault18;
    MockVault vault6;

    address alice = vm.randomAddress();
    address bob = vm.randomAddress();

    function setUp() public {
        asset18 = new MockAsset18();
        asset6 = new MockAsset6();

        MockVault vault18Impl = new MockVault();
        bytes memory vault18InitData = abi.encodeWithSelector(MockVault.initialize.selector, address(asset18), "Vault18", "V18");
        ERC1967Proxy proxy = new ERC1967Proxy(address(vault18Impl), vault18InitData);
        vault18 = MockVault(address(proxy));

        MockVault vault6Impl = new MockVault();
        bytes memory vault6InitData = abi.encodeWithSelector(MockVault.initialize.selector, address(asset6), "Vault6", "V6");
        ERC1967Proxy proxy6 = new ERC1967Proxy(address(vault6Impl), vault6InitData);
        vault6 = MockVault(address(proxy6));

        // fund alice with assets
        asset18.mint(alice, 1_000 ether);
        asset6.mint(alice, 1_000_000_000); // 1,000.000000 with 6 decimals
    }

    function test_Initialization() public {
        assertEq(vault18.asset(), address(asset18), "asset wired");
        assertEq(vault18.name(), "Vault18");
        assertEq(vault18.symbol(), "V18");
        // share decimals should equal underlying + offset(0)
        assertEq(vault18.decimals(), asset18.decimals());
        assertEq(vault6.decimals(), asset6.decimals());

        assertEq(vault18.totalAssets(), 0);
        assertEq(vault18.totalSupply(), 0);
        assertEq(vault18.checkpointNonce(), 0);
    }

    function test_PreviewAndConvert_Initial() public {
        // In empty vault with offset 0: 1:1
        assertEq(vault18.previewDeposit(100 ether), 100 ether);
        assertEq(vault18.previewMint(100 ether), 100 ether);
        assertEq(vault18.previewWithdraw(100 ether), 100 ether);
        assertEq(vault18.previewRedeem(100 ether), 100 ether);

        // same for 6 decimals
        assertEq(vault6.previewDeposit(1_000_000), 1_000_000);
        assertEq(vault6.previewMint(1_000_000), 1_000_000);
        assertEq(vault6.previewWithdraw(1_000_000), 1_000_000);
        assertEq(vault6.previewRedeem(1_000_000), 1_000_000);
    }

    function test_Deposit_Mint_and_Checkpoints() public {
        // Alice approves assets to vault
        vm.startPrank(alice);
        asset18.approve(address(vault18), type(uint256).max);

        // Deposit 200 assets -> should receive 200 shares
        uint256 shares = vault18.deposit(200 ether, alice);
        assertEq(shares, 200 ether);
        assertEq(vault18.balanceOf(alice), 200 ether);
        assertEq(vault18.totalSupply(), 200 ether);
        assertEq(vault18.totalAssets(), 200 ether);
        assertEq(vault18.checkpointNonce(), 1, "mint increments nonce");
        assertEq(vault18.totalSupplyAt(1), 200 ether);
        assertEq(vault18.balanceOfAt(alice, 1), 200 ether);

        // Mint 50 shares -> should deposit 50 assets
        uint256 assetsSpent = vault18.mint(50 ether, alice);
        assertEq(assetsSpent, 50 ether);
        assertEq(vault18.balanceOf(alice), 250 ether);
        assertEq(vault18.totalSupply(), 250 ether);
        assertEq(vault18.totalAssets(), 250 ether);
        assertEq(vault18.checkpointNonce(), 2, "second mint increments nonce");
        assertEq(vault18.totalSupplyAt(2), 250 ether);
        assertEq(vault18.balanceOfAt(alice, 2), 250 ether);
        vm.stopPrank();

        // Historical remains
        assertEq(vault18.totalSupplyAt(1), 200 ether);
        assertEq(vault18.balanceOfAt(alice, 1), 200 ether);
    }

    function test_Withdraw_Redeem_and_Allowances_and_Errors() public {
        // Prepare: Alice deposits 100, Bob will try to redeem for Alice
        vm.startPrank(alice);
        asset18.approve(address(vault18), type(uint256).max);
        vault18.deposit(100 ether, alice);
        vm.stopPrank();

        // maxWithdraw equals Alice assets value
        uint256 maxW = vault18.maxWithdraw(alice);
        assertEq(maxW, 100 ether);

        // Third-party withdraw path requires share allowance
        vm.prank(alice);
        vault18.approve(bob, 60 ether);

        // Bob withdraws 60 assets on behalf of Alice
        vm.prank(bob);
        uint256 burned = vault18.withdraw(60 ether, bob, alice);
        assertEq(burned, 60 ether); // shares burned
        assertEq(vault18.balanceOf(alice), 40 ether);
        assertEq(vault18.totalAssets(), 40 ether);
        assertEq(vault18.totalSupply(), 40 ether);
        assertEq(vault18.checkpointNonce(), 2, "deposit + withdraw");

        // Exceeding maxWithdraw should revert
        vm.expectRevert(abi.encodeWithSelector(
            ERC4626Checkpointed.ERC4626ExceededMaxWithdraw.selector, alice, uint256(50 ether), uint256(40 ether)
        ));
        vault18.withdraw(50 ether, alice, alice);

        // Redeem path, exceeding should revert
        vm.expectRevert(abi.encodeWithSelector(
            ERC4626Checkpointed.ERC4626ExceededMaxRedeem.selector, alice, uint256(50 ether), uint256(40 ether)
        ));
        vault18.redeem(50 ether, alice, alice);

        // Successful redeem of remaining 40 by alice
        vm.prank(alice);
        uint256 assetsOut = vault18.redeem(40 ether, alice, alice);
        assertEq(assetsOut, 40 ether);
        assertEq(asset18.balanceOf(alice), 940 ether);
        assertEq(vault18.totalAssets(), 0);
        assertEq(vault18.totalSupply(), 0);
        assertEq(vault18.balanceOf(alice), 0);
        assertEq(vault18.checkpointNonce(), 3, "deposit + withdraw + redeem");
    }

    function test_Donation_Impacts_SharePrice_and_Rounding() public {
        // Alice deposits 100 -> 100 shares
        vm.startPrank(alice);
        asset18.approve(address(vault18), type(uint256).max);
        vault18.deposit(100 ether, alice);
        vm.stopPrank();

        // External donation of 100 assets
        asset18.mint(address(vault18), 100 ether);
        assertEq(vault18.totalAssets(), 200 ether);
        assertEq(vault18.totalSupply(), 100 ether);

        // Now, previewDeposit for 100 assets should yield 50 shares (exchange rate 0.5)
        uint256 sharesFor100 = vault18.previewDeposit(100 ether);
        assertEq(sharesFor100, 50 ether);

        // previewWithdraw for 100 assets should require ~50 shares
        uint256 sharesToWithdraw100 = vault18.previewWithdraw(100 ether);
        assertGt(sharesToWithdraw100, 50 ether - 1); // rounding up, strictly > 50 if not exact division
        assertLt(sharesToWithdraw100, 50 ether + 2);
    }

    function test_Decimals_6() public {
        // Ensure 6-decimals asset flows 1:1 initially
        vm.startPrank(alice);
        asset6.approve(address(vault6), type(uint256).max);
        uint256 s = vault6.deposit(1_500_000, alice); // 1.5 tokens
        assertEq(s, 1_500_000);
        assertEq(vault6.totalAssets(), 1_500_000);
        assertEq(vault6.totalSupply(), 1_500_000);

        // Withdraw half
        uint256 burned = vault6.withdraw(750_000, alice, alice);
        assertEq(burned, 750_000);
        assertEq(vault6.totalAssets(), 750_000);
        assertEq(vault6.totalSupply(), 750_000);
        vm.stopPrank();
    }
}
