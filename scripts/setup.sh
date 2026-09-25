#!/bin/bash
# One-time setup for running Niyat on your own iPhone.
# Finds your Apple team ID, writes Config/Local.xcconfig and generates the Xcode project.
# Usage: make setup
set -e
cd "$(dirname "$0")/.."

bold() { printf "\033[1m%s\033[0m\n" "$1"; }

if ! ls -d /Applications/Xcode*.app >/dev/null 2>&1; then
  echo "Xcode isn't installed. Install it from the App Store, open it once, then run this again."
  exit 1
fi
if xcode-select -p 2>/dev/null | grep -q CommandLineTools; then
  echo "Your Mac is using the Command Line Tools instead of Xcode. Fix it with:"
  echo "  sudo xcode-select -s /Applications/Xcode.app"
  echo "then run this again."
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    bold "Installing XcodeGen…"
    brew install xcodegen
  else
    echo "Homebrew isn't installed. Install it from https://brew.sh, then run this again."
    exit 1
  fi
fi

# Look for team IDs Xcode knows about, then in signing certificates.
teams=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | grep -o 'teamID = [A-Z0-9]*' | awk '{print $3}' | sort -u)
if [ -z "$teams" ]; then
  teams=$(defaults read com.apple.dt.Xcode IDEProvisioningTeams 2>/dev/null | grep -o 'teamID = [A-Z0-9]*' | awk '{print $3}' | sort -u)
fi
if [ -z "$teams" ]; then
  teams=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | awk '/BEGIN CERT/{c=""} {c=c $0 "\n"} /END CERT/{print c | "openssl x509 -noout -subject"; close("openssl x509 -noout -subject")}' \
    | grep -o 'OU *= *[A-Z0-9]\{10\}' | grep -o '[A-Z0-9]\{10\}' | sort -u)
fi

team=""
count=$(printf "%s" "$teams" | grep -c . || true)
if [ "$count" = "1" ]; then
  team="$teams"
  bold "Found your team ID: $team"
elif [ "$count" -gt 1 ]; then
  bold "Found these team IDs:"
  echo "$teams"
  read -r -p "Type the one to use: " team
else
  echo "Couldn't find a team ID automatically."
  echo "Make sure you're signed in: Xcode > Settings > Accounts > + > Apple ID."
  read -r -p "Paste your team ID (or press Enter to pick it in Xcode later): " team
fi

default_prefix="com.$(whoami | tr -cd 'a-zA-Z0-9' | tr 'A-Z' 'a-z')"
read -r -p "App ID prefix, must be unique to you [$default_prefix]: " prefix
prefix=${prefix:-$default_prefix}

cat > Config/Local.xcconfig <<CONFIG
// Written by scripts/setup.sh. Git-ignored, so it stays on your Mac.
DEVELOPMENT_TEAM = $team
BUNDLE_ID_PREFIX = $prefix
CONFIG
bold "Saved Config/Local.xcconfig"

make project
bold "Done! Opening Xcode…"
echo "Pick your iPhone at the top of the Xcode window and press Run (the ▶ button)."
open Niyat.xcodeproj
