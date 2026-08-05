# SushiSwap V4 deployments

Canonical source-version and onchain deployment records for SushiSwap V4.

- `versions/` pins the exact Core and Periphery source used by a release.
- `plans/` pins the deployment account, nonce order, and expected deterministic addresses.
- `chains/` will contain one deployment manifest per chain after contracts are deployed.

The initial `v4-cl` release includes concentrated-liquidity contracts only. Sushi routing is maintained separately and is not deployed from the Infinity Periphery repository.

The initial Sushi pool policy is static-fee CL pools only. No official dynamic-fee hook is included in this release. The Core contracts retain their generic hook and dynamic-fee interfaces for independently developed or third-party hooks.

## Initial launch chains

- Ethereum
- Base
- Polygon
- Unichain
- World Chain
- Arbitrum
- BNB Chain
- Robinhood Chain

Core and Periphery keep one staged config per chain under `script/config/`. A value of `"0x"` is an
intentionally unresolved governance input. Deployment and ownership scripts reject placeholders when
the corresponding value is required.

Governance multisigs are sourced from the Sushi operations spreadsheet and direct confirmation from
Sushi operations. Ethereum, Base, Polygon, Arbitrum, BNB Chain, and Robinhood Chain are populated.
The sheet does not currently list Unichain or World Chain, so those two remain deliberately unresolved. Fixed wrapped-native token addresses
are sourced from `sushi-labs/sushi` at commit `30b6e3de015077a14b97dc072f38a08364c16716`.
The canonical Permit2 deployment at `0x000000000022d473030f116ddee9f6b43ac78ba3` was checked for
deployed bytecode on all eight launch chains.

Before deployment, each chain still requires:

1. Confirmation of the pool owner and protocol-fee-controller owner for Unichain and World Chain.
2. A decision on the protocol fee split; the inherited controller default is 33% of total swap fees.
3. Explorer verification settings.

The eight launch contracts use direct EVM `CREATE`, not CREATE2/CREATE3. Their addresses are determined
only by the dedicated deployment account and nonce, and are precomputed in `plans/v4-cl.json`. The
account must make exactly the eight contract-creation transactions at nonces 0 through 7 on every
chain. No registration, verification, ownership, cancellation, or unrelated transaction may be sent
from it until nonce 7 is complete on that chain. The scripts enforce the expected signer, nonce, and
address. Setup and governance handoff follow afterward.

Always simulate each step against the target RPC and wait for confirmation before submitting the next
nonce. A mined, reverted creation transaction still consumes its nonce; if that happens before nonce 7,
the planned addresses cannot be recovered from this deployment account on that chain. Stop the rollout
and choose either a fresh deployment account for every chain or explicitly abandon cross-chain address
parity.

## Local deployment environment

Copy `.env.example` to the ignored `.env` file and source it before running deployment commands. The template defines one DRPC URL per launch chain. Never commit `.env` or pass its private key on the command line in shared logs.
