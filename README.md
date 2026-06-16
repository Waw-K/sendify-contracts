# Sendify Contracts

Smart contracts for **Sendify** — a multi-chain batch token distribution protocol that sends tokens to hundreds of wallets in a single transaction (airdrops, TGEs, vesting, DAO payouts).

This repository contains **only** the Solidity contracts and a minimal Hardhat setup for compilation and review. It contains no keys, RPC endpoints, or deployment scripts.

## Audit Scope

| Contract | SLOC | Purpose |
|---|---:|---|
| `contracts/DisperseMulti.sol` | ~247 | Multi-token batch disperse in one tx, with treasury fee + affiliate split |
| `contracts/MerkleDistributor.sol` | ~195 | Claim-based airdrops via Merkle proofs |
| `contracts/DisperseToken.sol` | ~108 | Single-token / native batch disperse with fee handling |
| `contracts/AffiliateVault.sol` | ~28 | Holds affiliate fee shares; affiliates withdraw their own balance |
| **Total** | **~578** | |

Compiler: Solidity `0.8.20` / `0.8.28` (optimizer 200 runs, viaIR).
Dependencies: OpenZeppelin Contracts `^5.4.0` (`Ownable`, `Pausable`, `ReentrancyGuard`, `SafeERC20`, `MerkleProof`).

## Architecture

- **Disperse (`DisperseToken`, `DisperseMulti`)** — the user transfers tokens/native value to the contract within one call, which fans them out to all recipients. A flat platform fee goes to the treasury; an optional affiliate share is forwarded (to the `AffiliateVault` or directly to the affiliate wallet). Guarded by `ReentrancyGuard` and `Pausable`.
- **AffiliateVault** — trustless escrow: `deposit(affiliate)` credits a balance; `withdraw()` lets each affiliate withdraw only their own balance (`msg.sender`). No owner can move user balances.
- **MerkleDistributor** — an owner funds a distribution and sets a Merkle root; recipients `claim()` with a proof. Double-claims are prevented via a claimed bitmap.

## Key Invariants (for review)

1. A disperse call distributes exactly the recipient amounts; the fee + affiliate share are taken on top and never reduce recipient payouts.
2. `msg.value` must cover native distribution + fee + affiliate amount; excess/shortfall must revert (no stuck funds).
3. In `AffiliateVault`, an affiliate can never withdraw more than their credited balance, and no other party can withdraw it.
4. In `MerkleDistributor`, each leaf can be claimed at most once; only valid proofs against the active root succeed.
5. No reentrancy across token callbacks; external token calls use `SafeERC20`.

## Build & Test

```bash
npm install
npm run compile
npm test
```

## License

MIT
