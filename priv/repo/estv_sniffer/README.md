# ESTV ICTax Token Price Sniffer

Bulk-fetches daily cryptocurrency/token prices (in CHF) from the Swiss Federal Tax Administration (ESTV) [ICTax rate list](https://www.ictax.admin.ch/extern/de.html#/ratelist/2025).

No external dependencies — uses only Python 3 stdlib.

## How it works

The ICTax web form queries an internal REST API that is not publicly documented. This tool reverse-engineers the authentication flow:

1. Fetches session cookies from the main page
2. Obtains a CSRF token from `/extern/api/authentication/session.json`
3. POSTs to `/extern/api/coreGadget/tokenGadget.json` with the token name, date (as UTC milliseconds), and `X-CSRF-TOKEN` header
4. Sessions auto-refresh on 403 (expiry)

Weekends are skipped by default since the ESTV API returns no data for them.

## Usage

```bash
cd priv/repo/estv_sniffer

# List all available tokens (91 tokens including BTC, ETH, SOL, etc.)
python3 fetch_prices.py --list-tokens

# Fetch all 2025 weekday prices for ETH (~261 requests, ~80 seconds)
python3 fetch_prices.py --token ETH

# Fetch for a different year
python3 fetch_prices.py --token ETH --year 2024

# Multiple tokens
python3 fetch_prices.py --token ETH,BTC

# All 91 tokens for 2025 (~23,751 requests)
python3 fetch_prices.py

# Custom output filename
python3 fetch_prices.py --token ETH --output eth_2025.csv

# Include weekends (rows will have value_chf=None)
python3 fetch_prices.py --token ETH --include-weekends

# Adjust request delay (default 0.3s, be respectful to the server)
python3 fetch_prices.py --token ETH --delay 0.5
```

## Options

| Flag | Description |
|------|-------------|
| `--token TOKEN` | Token short name(s), comma-separated (e.g., `ETH,BTC`). Omit to fetch all tokens. |
| `--year YEAR` | Year to fetch prices for (default: `2025`). |
| `--list-tokens` | List available tokens and exit. |
| `--delay SECONDS` | Delay between requests in seconds (default: `0.3`). |
| `--include-weekends` | Include weekend dates (no price data available). |
| `--output FILE` | Output CSV filename (default: `estv_prices_{token}_{year}.csv`). |

## Output format

CSV with columns:

| Column | Description |
|--------|-------------|
| `date` | ISO 8601 date (`YYYY-MM-DD`) |
| `token` | Token short name (e.g., `ETH`) |
| `value_chf` | Price in CHF per denomination unit, or empty if no data |
| `denomination` | Denomination unit (typically `1`) |

Example:

```csv
date,token,value_chf,denomination
2025-01-02,ETH,3167.741013,1
2025-01-03,ETH,3259.607003,1
2025-01-06,ETH,3378.613697,1
2025-01-07,ETH,3158.696134,1
```

## Data source

Prices come from the ESTV ICTax rate list at [ictax.admin.ch](https://www.ictax.admin.ch/extern/de.html#/ratelist/2025). These are the official values used for Swiss tax declarations. The ESTV calculates them as an average across multiple trading platforms.
