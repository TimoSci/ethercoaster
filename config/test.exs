import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ethercoaster, Ethercoaster.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ethercoaster_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ethercoaster, EthercoasterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "AHAB0fOys6eOgMedX68eJY5WThxoKH3P/KNzRyYz4kdhjg9t/0/Klq7R3pqCUtIr",
  server: false

# In test we don't send emails
config :ethercoaster, Ethercoaster.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Route Beacon Chain HTTP calls through Req.Test for stubbing
config :ethercoaster, Ethercoaster.BeaconChain,
  req_options: [plug: {Req.Test, Ethercoaster.BeaconChain.Client}, retry: false]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
