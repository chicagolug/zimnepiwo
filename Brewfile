# Host contributor tooling for zimnepiwo development.
#
# This Brewfile is for the *host* you hack on this repo from — it installs
# nothing into the bootc image. The in-image Brewfiles live in
# custom/brew/*.Brewfile and ship at /usr/share/ublue-os/homebrew/.
#
# Install with:  brew bundle install
# Verify with:   brew bundle list --all

# Static analysis for build/*.sh (enforced by pr-validation.yml)
brew "shellcheck"
# Local task runner (Justfile / custom/ujust recipes)
brew "just"
# Git hook manager (.pre-commit-config.yaml)
brew "pre-commit"
# Linter for .github/workflows/*.yml
brew "actionlint"
