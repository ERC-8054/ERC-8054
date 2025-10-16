// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IERC20Checkpointed is IERC20, IERC20Metadata {

    /**
     * @dev Returns the value of tokens in existence at specified checkpoint.
     * @param checkpoint The checkpoint to get the total supply at.
     */
    function totalSupplyAt(uint256 checkpoint) external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account` at specified checkpoint.
     * @param account The account to get the balance of.
     * @param checkpoint The checkpoint to get the balance at.
     */
    function balanceOfAt(address account, uint256 checkpoint) external view returns (uint256);

    /**
     * @dev Returns the current checkpoint nonce.
     */
    function checkpointNonce() external view returns (uint256);
}