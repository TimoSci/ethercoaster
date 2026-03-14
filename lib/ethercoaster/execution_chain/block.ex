defmodule Ethercoaster.ExecutionChain.Block do
  @moduledoc """
  Higher-level block reward and fee recipient functions for the execution layer.
  """

  alias Ethercoaster.ExecutionChain.{Client, Eth}

  @doc """
  Returns the block rewards (priority fees/tips), validator (proposer), and fee recipient
  for a given block number.

  `block` can be a hex string (`"0x1234"`), an integer, or a tag (`"latest"`).

  Returns:
      {:ok, %{
        block_number: integer(),
        validator: String.t(),          # coinbase / fee recipient address
        fee_recipient: String.t(),      # same as validator (EL coinbase)
        base_fee_per_gas: integer(),    # in wei
        gas_used: integer(),
        total_priority_fees: integer(), # sum of tips in wei
        block_reward: integer()         # total priority fees (tips) in wei
      }}
  """
  @spec get_block_rewards(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def get_block_rewards(block) do
    block_hex = to_hex(block)

    with {:ok, block_data} when not is_nil(block_data) <- Eth.get_block_by_number(block_hex, true),
         {:ok, receipts} when is_list(receipts) <- Eth.get_block_receipts(block_hex) do
      base_fee = hex_to_int(block_data["baseFeePerGas"] || "0x0")
      gas_used = hex_to_int(block_data["gasUsed"])

      total_priority_fees = compute_priority_fees(block_data["transactions"], receipts, base_fee)

      {:ok,
       %{
         block_number: hex_to_int(block_data["number"]),
         validator: block_data["miner"],
         fee_recipient: block_data["miner"],
         base_fee_per_gas: base_fee,
         gas_used: gas_used,
         total_priority_fees: total_priority_fees,
         block_reward: total_priority_fees
       }}
    else
      {:ok, nil} -> {:error, :block_not_found}
      {:error, _} = error -> error
    end
  end

  @doc """
  Batch version of `get_block_rewards/1` for multiple block numbers.
  Returns a list of `{:ok, map()} | {:error, term()}`.
  """
  @spec get_block_rewards_batch([String.t() | integer()]) :: [{:ok, map()} | {:error, term()}]
  def get_block_rewards_batch(blocks) do
    calls =
      blocks
      |> Enum.flat_map(fn block ->
        hex = to_hex(block)
        [{"eth_getBlockByNumber", [hex, true]}, {"eth_getBlockReceipts", [hex]}]
      end)

    results = Client.batch(calls)

    results
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [{:ok, block_data}, {:ok, receipts}] when not is_nil(block_data) and is_list(receipts) ->
        base_fee = hex_to_int(block_data["baseFeePerGas"] || "0x0")
        gas_used = hex_to_int(block_data["gasUsed"])
        total_priority_fees = compute_priority_fees(block_data["transactions"], receipts, base_fee)

        {:ok,
         %{
           block_number: hex_to_int(block_data["number"]),
           validator: block_data["miner"],
           fee_recipient: block_data["miner"],
           base_fee_per_gas: base_fee,
           gas_used: gas_used,
           total_priority_fees: total_priority_fees,
           block_reward: total_priority_fees
         }}

      [{:ok, nil}, _] ->
        {:error, :block_not_found}

      [{:error, _} = error, _] ->
        error

      [_, {:error, _} = error] ->
        error
    end)
  end

  # Computes total priority fees (tips) paid to the block proposer.
  # For each transaction: tip = (effective_gas_price - base_fee) * gas_used
  defp compute_priority_fees(transactions, receipts, base_fee) do
    receipt_map = Map.new(receipts, fn r -> {r["transactionHash"], r} end)

    transactions
    |> Enum.reduce(0, fn tx, acc ->
      tx_hash = tx["hash"]
      receipt = Map.get(receipt_map, tx_hash)

      if receipt do
        effective_gas_price = hex_to_int(receipt["effectiveGasPrice"] || tx["gasPrice"] || "0x0")
        tx_gas_used = hex_to_int(receipt["gasUsed"])
        tip_per_gas = max(effective_gas_price - base_fee, 0)
        acc + tip_per_gas * tx_gas_used
      else
        acc
      end
    end)
  end

  defp to_hex(n) when is_integer(n), do: "0x" <> Integer.to_string(n, 16)
  defp to_hex("0x" <> _ = hex), do: hex
  defp to_hex(tag) when tag in ["latest", "earliest", "pending", "safe", "finalized"], do: tag
  defp to_hex(n) when is_binary(n), do: "0x" <> Integer.to_string(String.to_integer(n), 16)

  defp hex_to_int("0x" <> hex), do: String.to_integer(hex, 16)
  defp hex_to_int(n) when is_integer(n), do: n
  defp hex_to_int(_), do: 0
end
