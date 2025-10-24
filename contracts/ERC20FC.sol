// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";

import {ERC20Checkpointed} from "./ERC20Checkpointed.sol";
import {IERC20Checkpointed} from "./interfaces/IERC20Checkpointed.sol";

/**
 * @dev A forked and checkpointed ERC20 contract that is forked from IERC20Checkpointed at certain checkpoint nonce
 */
abstract contract ERC20FC is ERC20Checkpointed {
    using Checkpoints for Checkpoints.Trace208;
    using LibBitmap for LibBitmap.Bitmap;

    LibBitmap.Bitmap private _isForkedBalances;

    uint48 private immutable _checkpointedNonce;
    IERC20Checkpointed private immutable _checkpointedToken;

    uint8 private immutable _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * Both values are immutable: they can only be set once during construction.
     */
    constructor(string memory name_, string memory symbol_, uint48 checkpointedNonce_, address checkpointedToken_) {
        _checkpointedNonce = checkpointedNonce_;
        _checkpointedToken = IERC20Checkpointed(checkpointedToken_);
        _name = name_;
        _symbol = symbol_;
        // copy decimals from checkpointed token
        _decimals = _checkpointedToken.decimals();
        // copy total supply
        _totalSupply.push(_checkpointNonce, SafeCast.toUint208(_checkpointedToken.totalSupplyAt(checkpointedNonce_)));
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view virtual override returns (uint256) {
        if (_isForkedBalances.get(uint256(uint160(account)))) {
            return balanceOf(account);
        }
        return _checkpointedToken.balanceOfAt(account, _checkpointedNonce);
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        uint48 nonce = _checkpointNonce + 1;

        uint208 safeValue = SafeCast.toUint208(value);

        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply.push(_checkpointNonce, _totalSupply.latest() + safeValue);
        } else {
            uint208 fromBalance;
            if (_isForkedBalances.get(uint256(uint160(from)))) {
                fromBalance = _balances[from].latest();
            } else {
                fromBalance = SafeCast.toUint208(_checkpointedToken.balanceOfAt(from, _checkpointedNonce));
                _isForkedBalances.set(uint256(uint160(from)));
            }

            if (fromBalance < safeValue) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from].push(_checkpointNonce, fromBalance - safeValue);
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply.push(_checkpointNonce, _totalSupply.latest() - safeValue);
            }
        } else {
            uint208 toBalance;
            if (_isForkedBalances.get(uint256(uint160(to)))) {
                toBalance = _balances[to].latest();
            } else {
                toBalance = SafeCast.toUint208(_checkpointedToken.balanceOfAt(to, _checkpointedNonce));
                _isForkedBalances.set(uint256(uint160(to)));
            }
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to].push(_checkpointNonce, _balances[to].latest() + safeValue);
            }
        }

        emit Transfer(from, to, value);
    }
}
