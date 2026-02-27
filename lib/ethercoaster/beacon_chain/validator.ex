defmodule Ethercoaster.BeaconChain.Validator do
  @moduledoc """
  Beacon Chain `/eth/v{1,2,3}/validator/*` endpoints.
  """

  alias Ethercoaster.BeaconChain.Client

  # Duties

  @doc "Returns attester duties for the given `epoch`, posting `validator_indices`."
  def get_attester_duties(epoch, validator_indices),
    do: Client.post("/eth/v1/validator/duties/attester/#{epoch}", validator_indices)

  @doc "Returns proposer duties for the given `epoch`."
  def get_proposer_duties(epoch),
    do: Client.get("/eth/v1/validator/duties/proposer/#{epoch}")

  @doc "Returns sync committee duties for the given `epoch`, posting `validator_indices`."
  def get_sync_duties(epoch, validator_indices),
    do: Client.post("/eth/v1/validator/duties/sync/#{epoch}", validator_indices)

  # Block production

  @doc "Produces an unsigned block for the given `slot` with the provided `params`."
  def produce_block(slot, params \\ []),
    do: Client.get("/eth/v3/validator/blocks/#{slot}", params)

  @doc "Produces an unsigned blinded block for the given `slot` with the provided `params`."
  def produce_blinded_block(slot, params \\ []),
    do: Client.get("/eth/v1/validator/blinded_blocks/#{slot}", params)

  # Attestation

  @doc "Returns attestation data for the given `params` (slot, committee_index)."
  def get_attestation_data(params),
    do: Client.get("/eth/v1/validator/attestation_data", params)

  @doc "Returns an aggregate attestation for the given `params` (attestation_data_root, slot)."
  def get_aggregate_attestation(params),
    do: Client.get("/eth/v1/validator/aggregate_attestation", params)

  @doc "Submits signed aggregate and proofs."
  def submit_aggregate_and_proofs(proofs),
    do: Client.post("/eth/v1/validator/aggregate_and_proofs", proofs)

  # Subscriptions

  @doc "Subscribes to beacon committee subnets."
  def submit_beacon_committee_subscriptions(subscriptions),
    do: Client.post("/eth/v1/validator/beacon_committee_subscriptions", subscriptions)

  @doc "Subscribes to sync committee subnets."
  def submit_sync_committee_subscriptions(subscriptions),
    do: Client.post("/eth/v1/validator/sync_committee_subscriptions", subscriptions)

  # Proposer

  @doc "Prepares beacon proposers with fee recipient information."
  def prepare_beacon_proposer(proposers),
    do: Client.post("/eth/v1/validator/prepare_beacon_proposer", proposers)

  @doc "Registers validators with the builder network."
  def register_validator(registrations),
    do: Client.post("/eth/v1/validator/register_validator", registrations)

  # Liveness

  @doc "Returns liveness data for the given `epoch`, posting `validator_indices`."
  def get_liveness(epoch, validator_indices),
    do: Client.post("/eth/v1/validator/liveness/#{epoch}", validator_indices)
end
