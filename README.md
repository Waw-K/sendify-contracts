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

## Deployments

The same contract source is deployed identically across all supported chains. Live mainnet deployments:

| Chain | Chain ID | DisperseToken | DisperseMulti | AffiliateVault | MerkleDistributor |
|---|---|---|---|---|---|
| Ethereum | 1 | `0x724f3d58b76fb9414a9eab6a8349a1274c9d5ff3` | `0x1fbe742a53de3f252b4ae827efa1551c3f225d07` | `0xc83d484f62b5be7e344fca0acaca3dec0445f68b` | `0x6ba6b3dc62e713e4be642b11bd745d39d6074dd4` |
| BNB Chain | 56 | `0x9751326103a7a71edb7f7f89aad100f9ea118e4d` | `0xb1140a7259504dbb9949fe3317c67730883c87d5` | `0xe15f825a2e2d29243fb910bdb85940b3938bb360` | `0x331ea57398c70d29044fb0025fc82fd6024f2e43` |
| Base | 8453 | `0x28bfec05214cb07c9b432ebace7ec9ec3805961d` | `0xc464790161f41c0aa9222160722f6fae08ebaca0` | `0x592fad209cf82aeb5d5b4cbf84a4463fd8169c73` | `0x1fbe742a53de3f252b4ae827efa1551c3f225d07` |
| Arbitrum | 42161 | `0x3498c8a0cdf680dd8483edea98956d6f1d0b2a65` | `0xc464790161f41c0aa9222160722f6fae08ebaca0` | `0x592fad209cf82aeb5d5b4cbf84a4463fd8169c73` | `0x1fbe742a53de3f252b4ae827efa1551c3f225d07` |
| Avalanche | 43114 | `0xf038d63878ce7c25734bea71508467ee162ee0c9` | `0xc464790161f41c0aa9222160722f6fae08ebaca0` | `0x592fad209cf82aeb5d5b4cbf84a4463fd8169c73` | `0x1fbe742a53de3f252b4ae827efa1551c3f225d07` |
| Polygon | 137 | `0xd051c44117cef55d75e19343d7963a0688df5ea8` | `0xc464790161f41c0aa9222160722f6fae08ebaca0` | `0x592fad209cf82aeb5d5b4cbf84a4463fd8169c73` | `0x1fbe742a53de3f252b4ae827efa1551c3f225d07` |
| HyperEVM | 999 | `0x9e3e1db4fecbab6d87110a4c3381db546d165adb` | `0x9e3e1db4fecbab6d87110a4c3381db546d165adb` | `0xb3c895f755de044439938fface34fe801e3d30b2` | — |

Testnet (Sepolia, 11155111): DisperseToken `0xb3c895f755de044439938fface34fe801e3d30b2`, DisperseMulti `0xc9b5f821071754bbfb412f6084a27c0dd2c19006`, AffiliateVault `0xb7017338bac2e15cd7328617a79cf5200ce615ec`, MerkleDistributor `0x719ef11c3792c4f0f1853bbd4fd6d95f321c3666`.

> On HyperEVM, `DisperseToken` and `DisperseMulti` point to the same multi-capable contract. Solana distributions use the SPL token program directly (no EVM contract).

## Build & Test

```bash
npm install
npm run compile
npm test
```

## License

MIT
