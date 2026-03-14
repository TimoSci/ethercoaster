defmodule Ethercoaster.Transactions do
  import Ecto.Query

  alias Ethercoaster.Repo
  alias Ethercoaster.Transaction

  def list_transactions(opts \\ []) do
    base_query()
    |> apply_filters(opts)
    |> apply_sort(opts)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  def count_transactions(opts \\ []) do
    base_query()
    |> apply_filters(opts)
    |> Repo.aggregate(:count)
  end

  defp base_query do
    Transaction
    |> join(:inner, [t], tt in assoc(t, :type), as: :type)
    |> join(:inner, [t, type: tt], c in assoc(tt, :category), as: :category)
    |> join(:inner, [t, type: tt], e in assoc(tt, :event), as: :event)
    |> join(:inner, [t], v in assoc(t, :validator), as: :validator)
    |> preload([type: tt, category: c, event: e, validator: v],
      type: {tt, category: c, event: e}, validator: v
    )
  end

  defp apply_filters(query, opts) do
    query
    |> maybe_filter_validators(opts[:validator_ids])
    |> maybe_filter_type(opts[:type_name])
    |> maybe_filter_category(opts[:category_name])
    |> maybe_filter_event(opts[:event_name])
    |> maybe_filter_epoch(opts[:epoch])
  end

  defp maybe_filter_validators(query, nil), do: query
  defp maybe_filter_validators(query, []), do: query
  defp maybe_filter_validators(query, ids), do: where(query, [t], t.validator_id in ^ids)

  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, ""), do: query
  defp maybe_filter_type(query, name), do: where(query, [type: tt], tt.name == ^name)

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, ""), do: query
  defp maybe_filter_category(query, name), do: where(query, [category: c], c.name == ^name)

  defp maybe_filter_event(query, nil), do: query
  defp maybe_filter_event(query, ""), do: query
  defp maybe_filter_event(query, name), do: where(query, [event: e], e.name == ^name)

  defp maybe_filter_epoch(query, nil), do: query
  defp maybe_filter_epoch(query, ""), do: query

  defp maybe_filter_epoch(query, epoch) when is_integer(epoch) do
    where(query, [t], t.epoch == ^epoch)
  end

  defp maybe_filter_epoch(query, epoch) when is_binary(epoch) do
    case Integer.parse(epoch) do
      {n, ""} -> where(query, [t], t.epoch == ^n)
      _ -> query
    end
  end

  defp apply_sort(query, opts) do
    sort_by = opts[:sort_by] || :datetime
    sort_dir = opts[:sort_dir] || :desc

    case sort_by do
      :datetime -> order_by(query, [t], [{^sort_dir, t.datetime}])
      :amount -> order_by(query, [t], [{^sort_dir, t.amount}])
      :epoch -> order_by(query, [t], [{^sort_dir, t.epoch}])
      :validator -> order_by(query, [validator: v], [{^sort_dir, v.index}])
      :type -> order_by(query, [type: tt], [{^sort_dir, tt.name}])
      :category -> order_by(query, [category: c], [{^sort_dir, c.name}])
      :event -> order_by(query, [event: e], [{^sort_dir, e.name}])
      _ -> order_by(query, [t], [{^sort_dir, t.datetime}])
    end
  end

  defp apply_pagination(query, opts) do
    limit = opts[:limit] || 100
    offset = opts[:offset] || 0

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  def list_type_names do
    Ethercoaster.TransactionType
    |> select([t], t.name)
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  def list_category_names do
    Ethercoaster.TransactionCategory
    |> select([c], c.name)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  def list_event_names do
    Ethercoaster.TransactionEvent
    |> select([e], e.name)
    |> order_by([e], asc: e.name)
    |> Repo.all()
  end
end
