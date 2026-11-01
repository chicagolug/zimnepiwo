#!/usr/bin/env bash

# Exit on error, unset variable, or pipe failure
set -euo pipefail

######################################################
# Install Bitwarden CLI (bw) from GitHub Releases
######################################################
# Bitwarden Desktop ships as a Flatpak (see
# custom/flatpaks/default.preinstall: com.bitwarden.desktop). Its RPM
# installs to /opt/Bitwarden, which fails on ostree layouts where /opt
# is a symlink to var/opt, and the bitwarden/desktop repo stopped
# publishing releases in 2022 (all clients moved to bitwarden/clients).
#
# The CLI has no Flatpak, so install the `bw` binary from the monorepo:
# bitwarden/clients, newest non-prerelease `cli-v*` tag. Asset names:
#   x86_64:  bw-linux-<version>.zip
#   aarch64: bw-linux-arm64-<version>.zip
# The monorepo publishes no per-zip checksum file, so the download is
# verified by TLS + checking the extracted `bw` binary runs.
#
# Requires network + GitHub API access at build time. If GITHUB_TOKEN is
# mounted as a build secret (/run/secrets/GITHUB_TOKEN, see Containerfile),
# it is used as an Authorization bearer to avoid API rate limits.
#
# IMPORTANT CONVENTIONS:
# - Use dnf5 exclusively (never dnf or yum)
# - Always use -y flag for non-interactive operations
# - Remove temp files so they don't persist in the image layer
###############################################################################

ARCH="$(uname -m)"
case "${ARCH}" in
x86_64) ZIP_PATTERN='^bw-linux-[0-9].*\.zip$' ;;
aarch64) ZIP_PATTERN='^bw-linux-arm64-.*\.zip$' ;;
*)
	echo "ERROR: unsupported architecture for Bitwarden CLI: ${ARCH}" >&2
	exit 1
	;;
esac

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

CURL_AUTH_ARGS=()
if [[ -s /run/secrets/GITHUB_TOKEN ]]; then
	CURL_AUTH_ARGS=(-H "Authorization: Bearer $(cat /run/secrets/GITHUB_TOKEN)")
fi

echo "Installing Bitwarden CLI..."

RELEASES_URL="https://api.github.com/repos/bitwarden/clients/releases?per_page=50"

echo "Resolving latest Bitwarden CLI release from ${RELEASES_URL} ..."
curl -fsSL "${CURL_AUTH_ARGS[@]}" "${RELEASES_URL}" -o "${WORKDIR}/releases.json"

CLI_ZIP_URL="$(python3 -c "
import json, re, sys
zip_pattern = re.compile(sys.argv[1])
with open('${WORKDIR}/releases.json') as f:
    releases = json.load(f)
for release in releases:
    tag = release.get('tag_name', '')
    if not tag.startswith('cli-v'):
        continue
    if release.get('draft') or release.get('prerelease'):
        continue
    for asset in release.get('assets', []):
        name = asset.get('name', '')
        if zip_pattern.match(name):
            print(asset.get('browser_download_url', ''))
            sys.exit(0)
" "${ZIP_PATTERN}")"

if [[ -z "${CLI_ZIP_URL:-}" ]]; then
	echo "ERROR: no Bitwarden CLI bundle matching ${ZIP_PATTERN} found" >&2
	exit 1
fi

echo "Downloading ${CLI_ZIP_URL} ..."
curl -fSL "${CLI_ZIP_URL}" -o "${WORKDIR}/bw-cli.zip"

echo "Extracting bw binary..."
# python3 zipfile avoids depending on unzip being in the build container.
python3 -c "import zipfile; zipfile.ZipFile('${WORKDIR}/bw-cli.zip').extractall('${WORKDIR}/bw-extracted')"
if [[ ! -f "${WORKDIR}/bw-extracted/bw" ]]; then
	echo "ERROR: 'bw' binary not found in ${CLI_ZIP_URL}" >&2
	exit 1
fi

echo "Installing bw to /usr/local/bin/bw ..."
install -D -m 0755 "${WORKDIR}/bw-extracted/bw" /usr/local/bin/bw
/usr/local/bin/bw --version

echo "Bitwarden CLI installation completed successfully!"
# WORKDIR removed by EXIT trap (isolate + clean up: no repo file, no tmp files).
