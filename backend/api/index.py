"""Vercel entry point. Vercel looks for a WSGI callable named `app`."""
import os
import sys
from pathlib import Path

# Make the `config` and `apps` packages importable from the function bundle.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

from config.wsgi import application as app  # noqa: E402
