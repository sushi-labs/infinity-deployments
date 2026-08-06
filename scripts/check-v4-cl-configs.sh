#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="$(cd "${repo_dir}/../infinity-core" && pwd)"
periphery_dir="$(cd "${repo_dir}/../infinity-periphery" && pwd)"
plan="${repo_dir}/plans/v4-cl.json"

for command_name in cast forge jq; do
  command -v "${command_name}" >/dev/null || {
    echo "Missing required command: ${command_name}" >&2
    exit 1
  }
done

fail() {
  echo "V4 CL config check failed: $*" >&2
  exit 1
}

same_address() {
  [[ "${1,,}" == "${2,,}" ]]
}

deployer="$(jq -er '.deployer' "${plan}")"
version_manifest="${repo_dir}/versions/v4-cl.json"
expected_foundry_version="$(jq -er '.toolchain.foundryVersion' "${version_manifest}")"
expected_foundry_commit="$(jq -er '.toolchain.foundryCommit' "${version_manifest}")"
actual_foundry_version="$(forge --version)"
[[ "${actual_foundry_version}" == *"Version: ${expected_foundry_version}"* ]] || \
  fail "Foundry version does not match ${expected_foundry_version}"
[[ "${actual_foundry_version}" == *"Commit SHA: ${expected_foundry_commit}"* ]] || \
  fail "Foundry commit does not match ${expected_foundry_commit}"

deployment_count="$(jq -er '.deployments | length' "${plan}")"
[[ "${deployment_count}" == "8" ]] || fail "deployment plan must contain exactly eight CREATE transactions"

for nonce in $(seq 0 7); do
  planned_nonce="$(jq -er ".deployments[${nonce}].nonce" "${plan}")"
  [[ "${planned_nonce}" == "${nonce}" ]] || fail "deployment index ${nonce} has nonce ${planned_nonce}"

  planned_address="$(jq -er ".deployments[${nonce}].address" "${plan}")"
  computed_address="$(cast compute-address --nonce "${nonce}" "${deployer}" | awk '{print $NF}')"
  same_address "${planned_address}" "${computed_address}" || \
    fail "nonce ${nonce} address is ${planned_address}, expected ${computed_address}"
done

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

core_fields=(vault clPoolManager clProtocolFeeController clPoolManagerOwnerContract)
core_nonces=(0 1 2 3)
periphery_fields=(clPositionDescriptor clPositionManager clQuoter clTickLens)
periphery_nonces=(4 5 6 7)

for config in "${configs[@]}"; do
  core_config="${core_dir}/script/config/${config}.json"
  periphery_config="${periphery_dir}/script/config/${config}.json"
  chain_id="$(jq -er '.chainId' "${core_config}")"

  [[ "$(jq -er '.chainId' "${periphery_config}")" == "${chain_id}" ]] || \
    fail "${config} has mismatched Core and Periphery chain IDs"
  same_address "$(jq -er '.deployer' "${core_config}")" "${deployer}" || \
    fail "${config} Core deployer does not match the plan"
  same_address "$(jq -er '.deployer' "${periphery_config}")" "${deployer}" || \
    fail "${config} Periphery deployer does not match the plan"

  governance_owner="$(jq -er --arg chain_id "${chain_id}" '.governanceOwners[$chain_id]' "${plan}")"
  jq -e --arg chain_id "${chain_id}" '.verifiers[$chain_id].provider and .verifiers[$chain_id].apiUrl' \
    "${plan}" >/dev/null || fail "${config} has no verifier configuration"
  same_address "$(jq -er '.poolOwner' "${core_config}")" "${governance_owner}" || \
    fail "${config} pool owner does not match the plan"
  same_address "$(jq -er '.protocolFeeControllerOwner' "${core_config}")" "${governance_owner}" || \
    fail "${config} fee owner does not match the plan"
  same_address "$(jq -er '.owner' "${periphery_config}")" "${governance_owner}" || \
    fail "${config} descriptor owner does not match the plan"

  for index in "${!core_fields[@]}"; do
    configured_address="$(jq -er ".${core_fields[$index]}" "${core_config}")"
    planned_address="$(jq -er ".deployments[${core_nonces[$index]}].address" "${plan}")"
    same_address "${configured_address}" "${planned_address}" || \
      fail "${config} ${core_fields[$index]} does not match the plan"
  done

  for index in "${!periphery_fields[@]}"; do
    configured_address="$(jq -er ".${periphery_fields[$index]}" "${periphery_config}")"
    planned_address="$(jq -er ".deployments[${periphery_nonces[$index]}].address" "${plan}")"
    same_address "${configured_address}" "${planned_address}" || \
      fail "${config} ${periphery_fields[$index]} does not match the plan"
  done

  uri="$(jq -er '.clPositionDescriptorTokenUri' "${periphery_config}")"
  [[ "${uri}" == */ ]] || fail "${config} position token URI must end with /"
done

[[ "$(jq -er '.protocolFeePolicy.splitRatio' "${plan}")" == "330000" ]] || \
  fail "protocol fee split must be 330000"
[[ "$(jq -er '.protocolFeePolicy.denominator' "${plan}")" == "1000000" ]] || \
  fail "protocol fee denominator must be 1000000"

echo "SushiSwap V4 CL plan and all eight chain configs are consistent"
