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
Unichain and World Chain use the directly confirmed shared operations multisig. Fixed wrapped-native
token addresses are sourced from `sushi-labs/sushi` at commit `30b6e3de015077a14b97dc072f38a08364c16716`.
The canonical Permit2 deployment at `0x000000000022d473030f116ddee9f6b43ac78ba3` was checked for
deployed bytecode on all eight launch chains.

Explorer verification settings are pinned by chain in `plans/v4-cl.json`. Seven launch chains use
Etherscan API V2 with one `ETHERSCAN_API_KEY`; Robinhood Chain uses its official Blockscout endpoint.
Verification must be performed only after nonce 7 is mined, and does not require the deployment key.

The launch protocol share is configured to 33% of each static pool's total swap fee. Core setup
validates the deployed controller's `330000 / 1000000` split before registering and handing off the
CL contracts. Governance can change this ratio after handoff. The underlying controller caps the
protocol fee at 0.4% of volume per direction, so the exact 33% split applies only up to approximately
a 1.21% total swap fee. Dynamic-fee pools use a separately governed default protocol fee and are not
part of the official launch policy.

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

Each script config includes the target chain ID and aborts when paired with the wrong RPC. Before any
mainnet broadcast, run `scripts/check-v4-cl-configs.sh` and `scripts/rehearse-v4-cl.sh` from this
repository with the deployment environment loaded. The static check recomputes all eight CREATE
addresses, enforces the release's pinned Foundry toolchain, and compares the deployment plan,
governance owners, and both repositories' chain configs.
The rehearsal forks every launch chain into a local Anvil instance, executes the complete
nonce 0-7 sequence plus setup and governance handoff locally, and checks deployed code, immutables,
fee policy, and ownership state. It never broadcasts to a remote chain.

## Local deployment environment

Copy `.env.example` to the ignored `.env` file and source it before running deployment commands. The template defines one DRPC URL per launch chain. Never commit `.env` or pass its private key on the command line in shared logs.
