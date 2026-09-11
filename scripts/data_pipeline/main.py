#!/usr/bin/env python3
"""Entry point reserved for FHIR parsing and local Supabase ingestion."""

from __future__ import annotations

import argparse


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate the pipeline scaffold only.")
    arguments = parser.parse_args()
    if arguments.check:
        print("data-pipeline scaffold: ready (FHIR ingestion intentionally deferred)")
        return
    parser.print_help()


if __name__ == "__main__":
    main()
