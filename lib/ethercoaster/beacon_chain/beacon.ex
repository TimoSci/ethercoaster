defmodule Ethercoaster.BeaconChain.Beacon do
  @moduledoc """
  Beacon Chain `/eth/v{1,2}/beacon/*` endpoints.
  """

  alias Ethercoaster.BeaconChain.Client

  # Genesis

  @doc "Returns the genesis information."
  def get_genesis, do: Client.get("/eth/v1/beacon/genesis")

  # State

  @doc "Returns the state root for the given `state_id`."
  def get_state_root(state_id), do: Client.get("/eth/v1/beacon/states/#{state_id}/root")

  @doc "Returns the fork data for the given `state_id`."
  def get_state_fork(state_id), do: Client.get("/eth/v1/beacon/states/#{state_id}/fork")

  @doc "Returns finality checkpoints for the given `state_id`."
  def get_finality_checkpoints(state_id),
    do: Client.get("/eth/v1/beacon/states/#{state_id}/finality_checkpoints")

  # Validators

  @doc "Returns validators for the given `state_id`, optionally filtered by `params`."
  def get_validators(state_id, params \\ []),
    do: Client.get("/eth/v1/beacon/states/#{state_id}/validators", params)

  @doc "Returns a specific validator by `validator_id` at the given `state_id`."
  def get_validator(state_id, validator_id),
    do: Client.get("/eth/v1/beacon/states/#{state_id}/validators/#{validator_id}")

  @doc "Returns validator balances for the given `state_id`, optionally filtered by `params`."
  def get_validator_balances(state_id, params \\ []),
    do: Client.get("/eth/v1/beacon/states/#{state_id}/validator_balances", params)

  # Committees

  @doc "Returns committees for the given `state_id`, optionally filtered by `params`."
  def get_committees(state_id, params \\ []),
    do: Client.get("/eth/v1/beacon/states/#{state_id}/committees", params)

  # Headers

  @doc "Returns block headers, optionally filtered by `params`."
  def get_headers(params \\ []), do: Client.get("/eth/v1/beacon/headers", params)

  @doc "Returns the block header for the given `block_id`."
  def get_header(block_id), do: Client.get("/eth/v1/beacon/headers/#{block_id}")

  # Blocks

  @doc "Returns the block for the given `block_id`."
  def get_block(block_id), do: Client.get("/eth/v2/beacon/blocks/#{block_id}")

  @doc "Returns the block root for the given `block_id`."
  def get_block_root(block_id), do: Client.get("/eth/v1/beacon/blocks/#{block_id}/root")

  @doc "Returns attestations included in the block for the given `block_id`."
  def get_block_attestations(block_id),
    do: Client.get("/eth/v1/beacon/blocks/#{block_id}/attestations")

  # Blobs

  @doc "Returns blob sidecars for the given `block_id`."
  def get_blobs(block_id), do: Client.get("/eth/v1/beacon/blob_sidecars/#{block_id}")

  # Pool — reads

  @doc "Returns attestations from the operations pool, optionally filtered by `params`."
  def get_pool_attestations(params \\ []),
    do: Client.get("/eth/v1/beacon/pool/attestations", params)

  @doc "Returns attester slashings from the operations pool."
  def get_pool_attester_slashings, do: Client.get("/eth/v1/beacon/pool/attester_slashings")

  @doc "Returns proposer slashings from the operations pool."
  def get_pool_proposer_slashings, do: Client.get("/eth/v1/beacon/pool/proposer_slashings")

  @doc "Returns voluntary exits from the operations pool."
  def get_pool_voluntary_exits, do: Client.get("/eth/v1/beacon/pool/voluntary_exits")

  @doc "Returns sync committee messages from the operations pool."
  def get_pool_sync_committees, do: Client.get("/eth/v1/beacon/pool/sync_committees")

  # Pool — writes

  @doc "Submits attestations to the operations pool."
  def submit_pool_attestations(attestations),
    do: Client.post("/eth/v1/beacon/pool/attestations", attestations)

  @doc "Submits an attester slashing to the operations pool."
  def submit_pool_attester_slashing(slashing),
    do: Client.post("/eth/v1/beacon/pool/attester_slashings", slashing)

  @doc "Submits a proposer slashing to the operations pool."
  def submit_pool_proposer_slashing(slashing),
    do: Client.post("/eth/v1/beacon/pool/proposer_slashings", slashing)

  @doc "Submits a voluntary exit to the operations pool."
  def submit_pool_voluntary_exit(exit),
    do: Client.post("/eth/v1/beacon/pool/voluntary_exits", exit)

  @doc "Submits sync committee messages to the operations pool."
  def submit_pool_sync_committees(messages),
    do: Client.post("/eth/v1/beacon/pool/sync_committees", messages)

  # Rewards

  @doc "Returns sync committee rewards for `block_id`, posting `validator_ids` to filter."
  def get_sync_committee_rewards(block_id, validator_ids \\ []),
    do: Client.post("/eth/v1/beacon/rewards/sync_committee/#{block_id}", validator_ids)

  @doc "Returns attestation rewards for `epoch`, posting `validator_ids` to filter."
  def get_attestation_rewards(epoch, validator_ids \\ []),
    do: Client.post("/eth/v1/beacon/rewards/attestations/#{epoch}", validator_ids)
end
