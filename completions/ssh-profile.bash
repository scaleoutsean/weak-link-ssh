#!/bin/bash
# Bash completion for ssh-profile and ssh-legacy

_ssh_profile_completions() {
  local cur prev profiles dir p
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # complete first argument as profile names from /profiles or ~/.ssh/profiles
  if [ ${COMP_CWORD} -eq 1 ]; then
    profiles=""
    for dir in /profiles ~/.ssh/profiles; do
      if [ -d "$dir" ]; then
        for p in "$dir"/*; do
          [ -e "$p" ] || continue
          profiles+=" $(basename "$p")"
        done
      fi
    done
    COMPREPLY=( $(compgen -W "${profiles}" -- "$cur") )
    return 0
  fi

  # don't attempt to complete fingerprint values after --host-fp
  if [[ " ${COMP_WORDS[*]} " == *" --host-fp "* ]]; then
    return 0
  fi

  case "$prev" in
    --host-fp) return 0 ;;
    *) return 0 ;;
  esac
}
complete -F _ssh_profile_completions ssh-profile

_ssh_legacy_completions() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  opts="--host-fp -p -i -o --help"
  COMPREPLY=( $(compgen -W "${opts}" -- "$cur") )
}
complete -F _ssh_legacy_completions ssh-legacy
