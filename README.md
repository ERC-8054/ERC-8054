---
eip: XXXX
title: Forkable ERC-20 Standard
author: 
status: Draft
type: Standards Track
category: ERC
created: 2025-10-10
requires: ERC-20
---

# Forkable ERC-20 Standard (Draft)

## Abstract
The standard defines standardized interfaces for creating forkable ERC-20 and forked ERC-20 tokens. This standard is an extension of the ERC-20 standard.

## Motivation
Traditionally,
to mass send a new ERC-20 token that is derived from an existing ERC-20 token (source token) balance there are 2 main ways:
- The expensive route is to take a snapshot of the ERC-20 token balance and manually transfer the new ERC-20 token to the users who have positive balance at the snapshot.
- The cheaper and more common route is to create a merkle root of the rewards and let user claim the new ERC-20 token by providing the merkle proof.

Both methods are inefficient and prone to errors.

Hence, we propose a standard for forkable ERC-20 tokens and forked ERC-20 tokens that can be easily integrated with existing ERC-20 tokens.

Forking ERC-20 tokens allow for cheaper and more efficient token transfers that are based or proportionally derived from the source token balances.


## Use Cases
### Airdrops
Airdrops are a common use case for forkable tokens.
Without forkable ERC-20 tokens, manual snapshotting and merkle root creation is required.
Then users must manually claim the new ERC-20 token costing gas borne by the claimer.

With forkable ERC-20 tokens, users do not have to claim the new ERC-20 token.
The forked ERC-20 token is automatically transferred to the users who have positive balance at the fork point.

## Specification

### Forkable ERC-20 tokens (Source Token)
Forkable ERC-20 tokens are ERC-20 compliant tokens that have their balances and total supply saved at every update call.
It will also maintain a checkpoint nonce that is incremented every time a checkpoint is taken.

all forkable ERC-20 tokens:
- MUST implement ERC20
- MUST implement optional ERC20 metadata that includes:
    - name (string)
    - symbol (string)
    - decimals (uint8)

#### interface
```solidity
interface IERC20Checkpointed is IERC20, IERC20Metadata {

    /**
     * @dev Returns the value of tokens in existence at specified checkpoint.
     * @param checkpoint The checkpoint to get the total supply at.
     */
    function totalSupplyAt(uint256 checkpoint) external view virtual returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account` at specified checkpoint.
     * @param account The account to get the balance of.
     * @param checkpoint The checkpoint to get the balance at.
     */
    function balanceOfAt(address account, uint256 checkpoint) public view virtual returns (uint256);
}
```

#### Behaviour Specifications
- `totalSupplyAt` MUST return the total supply of tokens at the specified checkpoint.
- `balanceOfAt` MUST return the balance of tokens owned by `account` at the specified checkpoint.
- `totalSupply` MUST return the latest checkpointed total supply of tokens.
- `balanceOf` MUST return the latest checkpointed balance of token held by the account.
- Any state changes (transfer, mint, burn) MUST increment the checkpoint nonce.
- Any state changes (transfer, mint, burn) MUST push the latest checkpoint balances and total supply.


### Forked ERC-20 tokens
Forked ERC-20 tokens are ERC-20 compliant tokens that are derived from a checkpointed token at a given checkpoint nonce.

All forked ERC-20 tokens:
- MUST implement ERC-20
- MUST implement optional ERC-20 metadata that includes:
    - name (string)
    - symbol (string)
    - decimals (uint8)
- MUST take as constructor (or initializer) inputs:
    - name (string)
    - symbol (string)
    - checkpointedNonce (uint256)
    - checkpointedToken (address) implementing IERC20Checkpointed
- MUST set decimals equal to the source token’s decimals.
- Initial totalSupply MUST equal `IERC20Checkpointed(totalSupplyAt(checkpointedNonce))`.
- For any account A, the forked token’s initial balance MUST equal `IERC20Checkpointed(balanceOfAt(A, checkpointedNonce))`.
- After deployment, the forked token operates as a normal ERC-20. Subsequent state changes in the source token MUST NOT affect the forked token.

#### Behaviour Specifications
- `balanceOf` MUST return the result of `balanceOfAt(account, checkpointedNonce)` from the source token if no state change in the forked token has occurred since the fork.
- `balanceOf` MUST NOT query from the source token other than the initial checkpointed nonce.
- `totalSupply` MUST return the result of `totalSupplyAt(checkpointedNonce)` from the source token if no state change in the forked token has occurred since the fork.
- `totalSupply` MUST NOT query from the source token other than the initial checkpointed nonce.
- Any state changes MUST NOT affect the source token.

#### Operational notes
- Forked tokens are not checkpointed.
- Allowances and nonces are NOT carried over, integrators should treat the fork as a fresh ERC-20 for approvals and permits.
- If the source token does not implement IERC20Checkpointed, the fork mechanism is out-of-scope of this standard.

## Reference Implementation
This repository provides a minimal reference:
- contracts/Checkpoints.sol: lightweight checkpoint library (uint256-based) used in source tokens.
- contracts/ERC20Checkpointed.sol: ERC-20 with checkpointed balances and total supply.
- contracts/ERC20Forked.sol: ERC-20 forked from a checkpointed token at a given nonce.

## Security Considerations
- Approvals: Do not assume approvals migrate, wallets and dApps must re-approve.
- Non-standard tokens (Rebase/fee-on-transfer): Fork semantics at a block may not capture dynamic mechanics, auditors should review source token behavior.
- Decimals: Forked token decimals must match source token decimals to avoid balance inconsistency.
- Forking the future: While supplying a checkpoint nonce in the future is possible, it is not recommended as it may lead to unexpected behavior.

## Reference Tests
[TBA]

## Copyright
This work is made available under CC0-1.0. See LICENSE for repository licensing;
ERC text itself is dedicated to the public domain.

