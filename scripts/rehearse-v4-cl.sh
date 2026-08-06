#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="$(cd "${repo_dir}/../infinity-core" && pwd)"
periphery_dir="$(cd "${repo_dir}/../infinity-periphery" && pwd)"

if [[ -f "${repo_dir}/.env" ]]; then
  set -a
  source "${repo_dir}/.env"
  set +a
fi

: "${PRIVATE_KEY:?PRIVATE_KEY must be set in infinity-deployments/.env or the environment}"
export PRIVATE_KEY

for command_name in anvil cast forge jq; do
  command -v "${command_name}" >/dev/null || {
    echo "Missing required command: ${command_name}" >&2
    exit 1
  }
done

"${repo_dir}/scripts/check-v4-cl-configs.sh"

readonly expected_deployer="0xc299b6425Fbc3851ed0eaa3C75931CDc927a271c"
actual_deployer="$(cast wallet address --private-key "${PRIVATE_KEY}")"
if [[ "${actual_deployer,,}" != "${expected_deployer,,}" ]]; then
  echo "PRIVATE_KEY does not belong to the configured deployment account" >&2
  exit 1
fi

configs=(
  ethereum-mainnet
  base-mainnet
  polygon-mainnet
  unichain-mainnet
  worldchain-mainnet
  arbitrum-mainnet
  bsc-mainnet
  robinhood-mainnet
)

start_at="${START_AT:-${configs[0]}}"
started=false
valid_start=false
for known_config in "${configs[@]}"; do
  if [[ "${known_config}" == "${start_at}" ]]; then
    valid_start=true
    break
  fi
done
if [[ "${valid_start}" != true ]]; then
  echo "Unknown START_AT config: ${start_at}" >&2
  exit 1
fi

rpc_variables=(
  ETHEREUM_RPC_URL
  BASE_RPC_URL
  POLYGON_RPC_URL
  UNICHAIN_RPC_URL
  WORLDCHAIN_RPC_URL
  ARBITRUM_RPC_URL
  BSC_RPC_URL
  ROBINHOOD_RPC_URL
)

anvil_pid=""
cleanup() {
  if [[ -n "${anvil_pid}" ]]; then
    kill "${anvil_pid}" 2>/dev/null || true
    wait "${anvil_pid}" 2>/dev/null || true
    anvil_pid=""
  fi
}
trap cleanup EXIT INT TERM

run_script() {
  local working_dir="$1"
  local script_target="$2"
  local local_rpc="$3"
  local config="$4"
  (
    cd "${working_dir}"
    SCRIPT_CONFIG="${config}" forge script "${script_target}" \
      --rpc-url "${local_rpc}" \
      --broadcast \
      --slow \
      -vv
  )
}

verify_script() {
  local working_dir="$1"
  local script_target="$2"
  local local_rpc="$3"
  local config="$4"
  (
    cd "${working_dir}"
    SCRIPT_CONFIG="${config}" forge script "${script_target}" --rpc-url "${local_rpc}" -vv
  )
}

for index in "${!configs[@]}"; do
  config="${configs[$index]}"
  if [[ "${config}" == "${start_at}" ]]; then
    started=true
  fi
  if [[ "${started}" != true ]]; then
    continue
  fi

  rpc_variable="${rpc_variables[$index]}"
  remote_rpc="${!rpc_variable:-}"
  rehearsal_rpc_variable="${rpc_variable%_RPC_URL}_REHEARSAL_RPC_URL"
  if [[ -n "${!rehearsal_rpc_variable:-}" ]]; then
    remote_rpc="${!rehearsal_rpc_variable}"
  fi
  if [[ -z "${remote_rpc}" ]]; then
    echo "${rpc_variable} is not set" >&2
    exit 1
  fi

  port="$((18545 + index))"
  local_rpc="http://127.0.0.1:${port}"
  anvil_log="${TMPDIR:-/tmp}/sushi-v4-anvil-${config}.log"
  extra_anvil_args=()
  if [[ "${config}" == "worldchain-mainnet" ]]; then
    # World Chain's public DRPC endpoint intermittently fails eth_getProof account hydration.
    extra_anvil_args+=(--no-storage-caching)
  fi

  echo "Rehearsing ${config} on a local fork"
  anvil --fork-url "${remote_rpc}" \
    --accounts 0 \
    --compute-units-per-second 50 \
    --retries 10 \
    --fork-retry-backoff 1000 \
    "${extra_anvil_args[@]}" \
    --port "${port}" \
    --silent >"${anvil_log}" 2>&1 &
  anvil_pid="$!"

  ready=false
  for _ in {1..30}; do
    if cast chain-id --rpc-url "${local_rpc}" >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 1
  done
  if [[ "${ready}" != true ]]; then
    echo "Anvil failed to start for ${config}; see ${anvil_log}" >&2
    exit 1
  fi

  expected_chain_id="$(jq -r '.chainId' "${core_dir}/script/config/${config}.json")"
  actual_chain_id="$(cast chain-id --rpc-url "${local_rpc}")"
  if [[ "${actual_chain_id}" != "${expected_chain_id}" ]]; then
    echo "Fork chain ID ${actual_chain_id} does not match ${config} (${expected_chain_id})" >&2
    exit 1
  fi

  remote_nonce="$(cast nonce "${expected_deployer}" --rpc-url "${local_rpc}")"
  if [[ "${remote_nonce}" != "0" ]]; then
    echo "Deployment account nonce is ${remote_nonce} on ${config}; expected 0" >&2
    exit 1
  fi

  cast rpc --rpc-url "${local_rpc}" anvil_setBalance "${expected_deployer}" \
    0x21e19e0c9bab2400000 >/dev/null

  run_script "${core_dir}" "script/01_DeployVault.s.sol:DeployVaultScript" "${local_rpc}" "${config}"
  run_script "${core_dir}" "script/02_DeployCLPoolManager.s.sol:DeployCLPoolManagerScript" "${local_rpc}" "${config}"
  run_script "${core_dir}" "script/04_DeployCLProtocolFeeController.s.sol:DeployCLProtocolFeeControllerScript" "${local_rpc}" "${config}"
  run_script "${core_dir}" "script/06_DeployCLPoolManagerOwner.s.sol:DeployCLPoolManagerOwnerScript" "${local_rpc}" "${config}"
  run_script "${periphery_dir}" \
    "script/01_DeployCLPositionDescriptorOffchain.s.sol:DeployCLPositionDescriptorOffChainScript" \
    "${local_rpc}" "${config}"
  run_script "${periphery_dir}" "script/02_DeployCLPositionManager.s.sol:DeployCLPositionManagerScript" \
    "${local_rpc}" "${config}"
  run_script "${periphery_dir}" "script/04_DeployCLQuoter.s.sol:DeployCLQuoterScript" "${local_rpc}" "${config}"
  run_script "${periphery_dir}" "script/09_DeployCLTickLens.s.sol:DeployCLTickLensScript" "${local_rpc}" "${config}"

  run_script "${core_dir}" "script/08_ConfigureCL.s.sol:ConfigureCLScript" "${local_rpc}" "${config}"
  run_script "${periphery_dir}" \
    "script/11_TransferDescriptorOwnership.s.sol:TransferDescriptorOwnershipScript" \
    "${local_rpc}" "${config}"
  run_script "${core_dir}" "script/09_TransferPoolManagerOwner.s.sol:TransferGovernanceOwnership" \
    "${local_rpc}" "${config}"

  verify_script "${core_dir}" "script/10_VerifyCLDeployment.s.sol:VerifyCLDeploymentScript" \
    "${local_rpc}" "${config}"
  verify_script "${periphery_dir}" \
    "script/12_VerifyCLDeployment.s.sol:VerifyCLPeripheryDeploymentScript" \
    "${local_rpc}" "${config}"

  pool_owner="$(jq -r '.poolOwner' "${core_dir}/script/config/${config}.json")"
  fee_owner="$(jq -r '.protocolFeeControllerOwner' "${core_dir}/script/config/${config}.json")"
  vault="$(jq -r '.vault' "${core_dir}/script/config/${config}.json")"
  manager_owner="$(jq -r '.clPoolManagerOwnerContract' "${core_dir}/script/config/${config}.json")"
  fee_controller="$(jq -r '.clProtocolFeeController' "${core_dir}/script/config/${config}.json")"

  for governance in "${pool_owner}" "${fee_owner}"; do
    cast rpc --rpc-url "${local_rpc}" anvil_impersonateAccount "${governance}" >/dev/null
    cast rpc --rpc-url "${local_rpc}" anvil_setBalance "${governance}" 0x56bc75e2d63100000 >/dev/null
  done
  cast send --rpc-url "${local_rpc}" --unlocked --from "${pool_owner}" "${vault}" "acceptOwnership()" >/dev/null
  cast send --rpc-url "${local_rpc}" --unlocked --from "${pool_owner}" "${manager_owner}" "acceptOwnership()" >/dev/null
  cast send --rpc-url "${local_rpc}" --unlocked --from "${fee_owner}" "${fee_controller}" "acceptOwnership()" >/dev/null

  verify_script "${core_dir}" "script/10_VerifyCLDeployment.s.sol:VerifyCLDeploymentScript" \
    "${local_rpc}" "${config}"

  cleanup
  echo "Rehearsal passed: ${config}"
done

echo "All SushiSwap V4 CL rehearsals passed without remote broadcasts"
