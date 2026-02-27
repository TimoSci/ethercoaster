defmodule Ethercoaster.Repo do
  use Ecto.Repo,
    otp_app: :ethercoaster,
    adapter: Ecto.Adapters.Postgres
end
