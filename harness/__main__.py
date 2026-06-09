"""Entry point: `python -m harness baseline` / `python -m harness verify`."""

import sys

from .cli import main

if __name__ == "__main__":
    sys.exit(main())
