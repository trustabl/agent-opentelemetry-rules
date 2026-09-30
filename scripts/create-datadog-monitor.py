#!/usr/bin/env python3
"""
Create the trustabl.tool_loop Datadog monitor from translations/datadog/monitor.json.

Prerequisites:
  pip install datadog-api-client

Usage:
  DD_API_KEY=<key> DD_APP_KEY=<key> python scripts/create-datadog-monitor.py
  # or with a specific site:
  DD_SITE=us3.datadoghq.com DD_API_KEY=<key> DD_APP_KEY=<key> python scripts/create-datadog-monitor.py
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

MONITOR_JSON = Path(__file__).parent.parent / "translations" / "datadog" / "monitor.json"


def main() -> None:
    api_key = os.environ.get("DD_API_KEY")
    app_key = os.environ.get("DD_APP_KEY")
    site = os.environ.get("DD_SITE", "datadoghq.com")

    if not api_key or not app_key:
        print(
            "ERROR: DD_API_KEY and DD_APP_KEY env vars are required.\n"
            "  Get them from:\n"
            "    API key:  https://app.datadoghq.com/organization-settings/api-keys\n"
            "    APP key:  https://app.datadoghq.com/organization-settings/application-keys",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        from datadog_api_client import ApiClient, Configuration
        from datadog_api_client.v1.api.monitors_api import MonitorsApi
        from datadog_api_client.v1.model.monitor import Monitor
    except ImportError:
        print(
            "ERROR: datadog-api-client is not installed.\n"
            "  pip install datadog-api-client",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(MONITOR_JSON, encoding="utf-8") as f:
        monitor_def = json.load(f)

    config = Configuration()
    config.api_key["apiKeyAuth"] = api_key
    config.api_key["appKeyAuth"] = app_key
    config.server_variables["site"] = site

    with ApiClient(config) as client:
        api = MonitorsApi(client)
        result = api.create_monitor(Monitor(**monitor_def))
        print(f"Created monitor id={result.id}  name={result.name}")
        print(f"View at: https://app.{site}/monitors/{result.id}")


if __name__ == "__main__":
    main()
