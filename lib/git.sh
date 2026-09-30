#!/usr/bin/env bash
# Global git configuration.
# shellcheck shell=bash

GIT_NAME_DEFAULT="${DMS_GIT_NAME:-Michael Zhang}"
GIT_EMAIL_WORK="michael.zhang@navex.com"
GIT_EMAIL_PERSONAL="zhang1605@gmail.com"

choose_git_identity() {
  if [[ -n ${GIT_EMAIL_ARG:-} ]]; then
    case "$GIT_EMAIL_ARG" in
      navex|work)      GIT_EMAIL="$GIT_EMAIL_WORK" ;;
      personal|gmail)  GIT_EMAIL="$GIT_EMAIL_PERSONAL" ;;
      *)               GIT_EMAIL="$GIT_EMAIL_ARG" ;;
    esac
    return 0
  fi

  local choice
  choice="$(ui_select "git user.email for this machine" \
    "work|$GIT_EMAIL_WORK" \
    "personal|$GIT_EMAIL_PERSONAL" \
    "custom|enter a different address…")"

  case "$choice" in
    work)     GIT_EMAIL="$GIT_EMAIL_WORK" ;;
    personal) GIT_EMAIL="$GIT_EMAIL_PERSONAL" ;;
    custom)   GIT_EMAIL="$(ui_ask 'Email:' "$GIT_EMAIL_WORK")" ;;
  esac
}

configure_git() {
  step "git global config"
  have git || { warn "git missing"; return 1; }

  local name
  name="$(ui_ask 'git user.name:' "$GIT_NAME_DEFAULT")"

  git config --global core.editor "nvim"
  git config --global init.defaultBranch main
  git config --global user.email "$GIT_EMAIL"
  git config --global user.name "$name"

  # Sensible extras that don't change any behaviour you'd be surprised by.
  git config --global pull.ff only
  git config --global push.autoSetupRemote true
  git config --global rebase.autostash true
  git config --global diff.colorMoved zebra

  ok "user.name  = $name"
  ok "user.email = $GIT_EMAIL"
  ok "core.editor = nvim, init.defaultBranch = main"
}
