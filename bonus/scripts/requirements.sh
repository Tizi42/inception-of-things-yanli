#!/usr/bin/env bash

# Shared, side-effect-free prerequisite checks for bonus scripts.

require_commands() {
  local command_name
  local -a missing_commands=()

  for command_name in "$@"; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
      missing_commands+=("${command_name}")
    fi
  done

  if (( ${#missing_commands[@]} == 0 )); then
    return 0
  fi

  for command_name in "${missing_commands[@]}"; do
    printf "ERROR: required tool '%s' was not found in PATH.\n" "${command_name}" >&2
  done
  echo "Install the missing tool(s) locally, make them available in PATH, and rerun this script." >&2
  echo "No installation was attempted." >&2
  return 127
}

require_docker_access() {
  if docker info >/dev/null 2>&1; then
    return 0
  fi

  echo "ERROR: Docker is installed, but its daemon is not available to the current user." >&2
  echo "Start or configure a user-accessible Docker daemon, then rerun this script." >&2
  echo "No privileged command was attempted." >&2
  return 1
}
