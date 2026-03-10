# Endpoint configuration — copy this file to endpoints.exs and edit.
#
# The first endpoint marked `default: true` will be used as the beacon chain
# API base URL. All endpoints listed here are seeded into the database
# when running `mix run priv/repo/seeds.exs`.
#
# This file (endpoints.exs) is gitignored and private to your machine.

[
  %{url: "http://localhost:5052", default: true},
  # %{url: "http://192.168.1.100:5052"},
  # %{url: "https://beacon.example.com:443"}
]
