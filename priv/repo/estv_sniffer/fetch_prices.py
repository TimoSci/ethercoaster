#!/usr/bin/env python3
"""
ESTV ICTax Token Price Sniffer

Fetches daily cryptocurrency/token prices from the Swiss Federal Tax
Administration (ESTV) ICTax rate list API for an entire year.

Usage:
    python3 fetch_prices.py                          # All tokens, 2025
    python3 fetch_prices.py --token ETH              # ETH only
    python3 fetch_prices.py --token ETH --year 2024  # ETH, 2024
    python3 fetch_prices.py --token ETH,BTC          # Multiple tokens
    python3 fetch_prices.py --list-tokens             # List available tokens

Output: CSV file written to estv_prices_{token}_{year}.csv
"""

import argparse
import csv
import json
import sys
import time
from datetime import date, datetime, timedelta, timezone

import urllib.request
import urllib.error

BASE_URL = "https://www.ictax.admin.ch/extern/api"
SESSION_URL = f"{BASE_URL}/authentication/session.json"
TOKENS_URL = f"{BASE_URL}/coreGadget/tokens.json"
TOKEN_GADGET_URL = f"{BASE_URL}/coreGadget/tokenGadget.json"

# Default delay between requests to be respectful to the server
DEFAULT_DELAY = 0.3  # seconds


def get_session():
    """Establish a session and return (cookie_header, csrf_token)."""
    # Step 1: Visit the main page to get session cookies
    req = urllib.request.Request("https://www.ictax.admin.ch/extern/de.html")
    resp = urllib.request.urlopen(req)
    cookies = []
    for header in resp.headers.get_all("Set-Cookie") or []:
        cookie_part = header.split(";")[0]
        cookies.append(cookie_part)
    cookie_header = "; ".join(cookies)

    # Step 2: Get CSRF token from session endpoint
    req = urllib.request.Request(SESSION_URL)
    req.add_header("Cookie", cookie_header)
    resp = urllib.request.urlopen(req)
    # Capture any new cookies from this response too
    for header in resp.headers.get_all("Set-Cookie") or []:
        cookie_part = header.split(";")[0]
        if cookie_part not in cookies:
            cookies.append(cookie_part)
    cookie_header = "; ".join(cookies)

    data = json.loads(resp.read().decode("utf-8"))
    csrf_token = data["data"]["csrfToken"]
    return cookie_header, csrf_token


def list_tokens(cookie_header):
    """Fetch and return the list of available token short names."""
    req = urllib.request.Request(TOKENS_URL)
    req.add_header("Cookie", cookie_header)
    resp = urllib.request.urlopen(req)
    data = json.loads(resp.read().decode("utf-8"))
    return sorted(t["token"]["shortName"] for t in data["data"])


def date_to_utc_millis(d):
    """Convert a date to UTC midnight timestamp in milliseconds."""
    dt = datetime(d.year, d.month, d.day, tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)


def fetch_token_price(token, reference_date, cookie_header, csrf_token):
    """Fetch the price for a single token on a single date."""
    payload = json.dumps({
        "from": 0,
        "size": 10,
        "tokens": [token],
        "referenceDate": date_to_utc_millis(reference_date),
    }).encode("utf-8")

    req = urllib.request.Request(TOKEN_GADGET_URL, data=payload, method="POST")
    req.add_header("Cookie", cookie_header)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    req.add_header("X-CSRF-TOKEN", csrf_token)

    try:
        resp = urllib.request.urlopen(req)
        data = json.loads(resp.read().decode("utf-8"))
        if data["status"] == "SUCCESS" and data["data"]["tokens"]:
            token_data = data["data"]["tokens"][0]
            return token_data.get("value"), token_data.get("denomination")
        return None, None
    except urllib.error.HTTPError as e:
        if e.code == 403:
            # Session expired, re-raise to trigger re-auth
            raise
        print(f"  HTTP {e.code} for {token} on {reference_date}", file=sys.stderr)
        return None, None
    except Exception as e:
        print(f"  Error for {token} on {reference_date}: {e}", file=sys.stderr)
        return None, None


def generate_dates(year, include_weekends=False):
    """Generate dates in a year up to today (exclusive).

    Skips weekends by default since the ESTV API has no data for them.
    """
    start = date(year, 1, 1)
    end = min(date(year, 12, 31), date.today() - timedelta(days=1))
    current = start
    while current <= end:
        if include_weekends or current.weekday() < 5:
            yield current
        current += timedelta(days=1)


def fetch_all_prices(token, year, delay=DEFAULT_DELAY, include_weekends=False):
    """Fetch all daily prices for a token in a given year."""
    print(f"Establishing session...", file=sys.stderr)
    cookie_header, csrf_token = get_session()

    dates = list(generate_dates(year, include_weekends=include_weekends))
    print(f"Fetching {len(dates)} days for {token} ({year})...", file=sys.stderr)

    results = []
    retries = 0

    for i, d in enumerate(dates):
        if i > 0 and i % 50 == 0:
            print(f"  Progress: {i}/{len(dates)} days", file=sys.stderr)

        try:
            value, denomination = fetch_token_price(
                token, d, cookie_header, csrf_token
            )
        except urllib.error.HTTPError as e:
            if e.code == 403 and retries < 3:
                retries += 1
                print(f"  Session expired, re-authenticating (attempt {retries})...",
                      file=sys.stderr)
                cookie_header, csrf_token = get_session()
                time.sleep(delay)
                value, denomination = fetch_token_price(
                    token, d, cookie_header, csrf_token
                )
            else:
                raise

        results.append({
            "date": d.isoformat(),
            "token": token,
            "value_chf": value,
            "denomination": denomination,
        })

        time.sleep(delay)

    return results


def write_csv(results, filename):
    """Write results to a CSV file."""
    with open(filename, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["date", "token", "value_chf", "denomination"])
        writer.writeheader()
        writer.writerows(results)
    print(f"Wrote {len(results)} rows to {filename}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description="Fetch daily token prices from ESTV ICTax"
    )
    parser.add_argument(
        "--token", type=str, default=None,
        help="Token short name(s), comma-separated (e.g., ETH,BTC). Default: all tokens"
    )
    parser.add_argument(
        "--year", type=int, default=2025,
        help="Year to fetch prices for (default: 2025)"
    )
    parser.add_argument(
        "--list-tokens", action="store_true",
        help="List available tokens and exit"
    )
    parser.add_argument(
        "--delay", type=float, default=DEFAULT_DELAY,
        help=f"Delay between requests in seconds (default: {DEFAULT_DELAY})"
    )
    parser.add_argument(
        "--include-weekends", action="store_true",
        help="Include weekends (no data available, but included for completeness)"
    )
    parser.add_argument(
        "--output", type=str, default=None,
        help="Output CSV filename (default: estv_prices_{token}_{year}.csv)"
    )
    args = parser.parse_args()

    delay = args.delay

    if args.list_tokens:
        cookie_header, _ = get_session()
        tokens = list_tokens(cookie_header)
        print("Available tokens:")
        for t in tokens:
            print(f"  {t}")
        return

    if args.token:
        tokens = [t.strip().upper() for t in args.token.split(",")]
    else:
        print("Fetching list of available tokens...", file=sys.stderr)
        cookie_header, _ = get_session()
        tokens = list_tokens(cookie_header)
        print(f"Found {len(tokens)} tokens: {', '.join(tokens)}", file=sys.stderr)

    all_results = []
    for token in tokens:
        results = fetch_all_prices(
            token, args.year, delay=delay,
            include_weekends=args.include_weekends,
        )
        all_results.extend(results)

    token_label = ",".join(tokens) if len(tokens) <= 3 else f"{len(tokens)}tokens"
    filename = args.output or f"estv_prices_{token_label}_{args.year}.csv"
    write_csv(all_results, filename)


if __name__ == "__main__":
    main()
