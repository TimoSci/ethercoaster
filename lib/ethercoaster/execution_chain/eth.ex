defmodule Ethercoaster.ExecutionChain.Eth do
  @moduledoc """
  Ethereum execution layer `eth_*` JSON-RPC methods.
  """

  alias Ethercoaster.ExecutionChain.Client

  @doc "Returns the block for the given hex block number or tag (\"latest\", \"finalized\", etc.)."
  def get_block_by_number(block, full_transactions \\ false),
    do: Client.call("eth_getBlockByNumber", [block, full_transactions])

  @doc "Returns the block for the given block hash."
  def get_block_by_hash(hash, full_transactions \\ false),
    do: Client.call("eth_getBlockByHash", [hash, full_transactions])

  @doc "Returns all transaction receipts for a block by number."
  def get_block_receipts(block),
    do: Client.call("eth_getBlockReceipts", [block])

  @doc "Returns the transaction receipt for the given transaction hash."
  def get_transaction_receipt(tx_hash),
    do: Client.call("eth_getTransactionReceipt", [tx_hash])

  @doc "Returns the current block number as a hex string."
  def block_number, do: Client.call("eth_blockNumber")

  @doc "Returns the balance of an address at the given block."
  def get_balance(address, block \\ "latest"),
    do: Client.call("eth_getBalance", [address, block])

  @doc "Returns the chain ID."
  def chain_id, do: Client.call("eth_chainId")
end
