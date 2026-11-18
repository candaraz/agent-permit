# AgentPermit

Standing spend permits between Binance **Agent ID** (`.ai`) holders on BNB Chain.

A permit lets an Agent ID holder (the *principal*) cap how much another Agent ID
holder (the *spender*) may send it, for a bounded window. No funds are ever held
by the contract: the only value movement possible is BNB sent by the spender to
the principal, bounded by the permit cap and expiry.

**Contract (BNB Chain):** `0x25dfbcffcc844012f7dab492e863906de5a5609b`
**Verified:** Sourcify `exact_match` (creation + runtime)
**Source:** this repository

## Why Agent ID is load-bearing

Agent ID is not a sticker here. Every state-changing entry point checks the
SPACE ID Agent ID registry on-chain:

| Action | Requirement |
| --- | --- |
| `mintBadge()` | caller holds an Agent ID |
| `createPermit()` | **both** principal and spender hold an Agent ID |
| `spend()` | the spender still holds an Agent ID |
| `revoke()` | only the principal |

The registry lives at `0x60b9262456de011f7d15a54cdd8c48baaa8b022f` (ERC-721,
soulbound, one per user). This contract only reads `balanceOf` and `handleOf`
from it. It never resolves a handle back to an address.

## Permission disclosure

The contract has **no owner, no admin, no fee, no pause, no upgrade, no
blacklist, no tax, and no arbitrary transfer function**. The registry address
and the badge supply cap are immutable. A permit can only move BNB from its own
spender to its own principal, and only while it is active and under cap. The
principal can revoke at any time. There is no path by which a third party's
funds move.

## API

```
mintBadge()                       -> uint256 tokenId   // free, one per Agent ID holder
holdsAgentId(address)             -> bool
handleOf(address)                 -> string            // .ai handle, display only
createPermit(spender, cap, duration) -> uint256 permitId
spend(permitId) payable           // spender sends value to the principal
revoke(permitId)                  // principal only
remaining(permitId)               -> uint256
isActive(permitId)                -> bool
permitInfo(permitId)              -> (principal, spender, handle, cap, spent, expiry, revoked)
permitsOf(principal)              -> uint256[]
badgeOf(address)                  -> uint256
```

Duration is bounded to 1 hour – 30 days. `cap` and `spent` are in wei.

## Badge

One ERC-721 badge per Agent ID holder, free, gas only. The metadata is fully
on-chain: the holder's `.ai` handle is rendered as an SVG inside a standard
ERC-721 JSON metadata document. No IPFS, no external image host.

## Development

```bash
forge build
forge test
```

The test suite covers the Agent ID gate on every entry point, single-mint
enforcement, free minting, cap enforcement, expiry, revocation, and the case
where a spender loses its Agent ID mid-permit.

## Deploy

The contract was deployed through the permissionless CREATE2 deployer proxy
`0x4e59b44847b379578588920cA78FbF26c0B4956C` (calldata layout: salt ++
initcode), which keeps the deploy reproducible from the Agent ID wallet.

## Licence

MIT.
