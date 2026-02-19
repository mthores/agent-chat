#!/usr/bin/env bash
# Shared helpers for agent-chat scripts.

SESSIONS_LOCK_DIR="$HOME/agent-chat/.sessions.lock"

sessions_lock() {
  for _ in $(seq 1 50); do
    mkdir "$SESSIONS_LOCK_DIR" 2>/dev/null && return 0
    sleep 0.1
  done
  # Timeout after 5s — assume stale lock from a crashed process
  rmdir "$SESSIONS_LOCK_DIR" 2>/dev/null || rm -rf "$SESSIONS_LOCK_DIR" 2>/dev/null || true
  mkdir "$SESSIONS_LOCK_DIR" 2>/dev/null || true
}

sessions_unlock() {
  rmdir "$SESSIONS_LOCK_DIR" 2>/dev/null || true
}
