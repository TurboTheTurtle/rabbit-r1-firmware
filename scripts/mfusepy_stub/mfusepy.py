"""Minimal stand-in for mfusepy on macOS (no libfuse installed).

mtkclient imports mfusepy only to expose an optional FUSE mount of the DA
filesystem. Its own fallback is `except ImportError`, but the real mfusepy
raises OSError('Unable to find libfuse') at import time, which escapes that
guard and aborts the whole CLI. Putting this stub earlier on PYTHONPATH makes
the import succeed so the non-FUSE code paths (printgpt / read partitions)
work.

FUSE is None on purpose: mtkclient treats that as "no fuse", matching the
fallback it already has for ImportError.
"""


class LoggingMixIn:
    pass


class Operations:
    pass


FUSE = None
