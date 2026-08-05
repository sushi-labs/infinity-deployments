# SushiSwap V4 deployments

Canonical source-version and onchain deployment records for SushiSwap V4.

- `versions/` pins the exact Core and Periphery source used by a release.
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

Core and Periphery keep one staged config per chain under `script/config/`. A value of `"0x"` or a zero gas limit is an intentionally unresolved input or an address that is filled after an earlier deployment step. Deployment scripts reject those placeholders when the corresponding value is required.

Fixed wrapped-native token and Sushi operations multisig addresses are sourced from `sushi-labs/sushi` at commit `30b6e3de015077a14b97dc072f38a08364c16716`. Unichain and World Chain operations multisigs are not defined there and remain unresolved. The canonical Permit2 deployment at `0x000000000022d473030f116ddee9f6b43ac78ba3` was checked for deployed bytecode on all eight launch chains.

Before deployment, each chain still requires:

1. A Sushi-authorized CREATE3 factory address.
2. Confirmation of the pool owner and protocol-fee-controller owner; Unichain and World Chain need both addresses supplied.
3. A non-zero CL position-manager unsubscribe gas limit.
4. RPC, explorer verification settings, and a funded deployment signer supplied through the deployment environment.

Vault, CL PoolManager, protocol fee controller, PoolManager owner, position descriptor, position manager, quoter, and tick lens addresses are deployment outputs. Record each output in the active chain config before running its dependent step, then publish the final addresses under `chains/`.

## Local deployment environment

Copy `.env.example` to the ignored `.env` file and source it before running deployment commands. The template defines one DRPC URL per launch chain. Never commit `.env` or pass its private key on the command line in shared logs.
