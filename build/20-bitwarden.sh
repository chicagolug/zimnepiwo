#!/usr/bin/env bash

# Exit on error, unset variable, or pipe failure
set -euo pipefail

######################################################
# Install Bitwarden Desktop + CLI from GitHub Releases
######################################################
# Bitwarden publishes Linux artifacts as release assets on GitHub — there is
# no version-less clean URL and no yum repo:
#   Desktop: bitwarden/desktop, matching arch RPM (e.g. Bitwarden-x86_64.rpm)
#   CLI:     bitwarden/cli, bw-linux-<version>.zip containing the `bw` binary
#            plus a bw-linux-sha256-<version>.txt checksum file.
# This script resolves each latest release via the GitHub API, downloads to a
# temp dir, verifies, installs, and cleans up. Follows the 20-onepassword.sh
# isolate + clean up convention: no repo file to leave behind because there
# is no repo, and no temp files left in the image layer.
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
x86_64) RPM_PATTERN='x86_64\.rpm$' ;;
aarch64) RPM_PATTERN='aarch64\.rpm$' ;;
*)
	echo "ERROR: unsupported architecture for Bitwarden RPM: ${ARCH}" >&2
	exit 1
	;;
esac

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

CURL_AUTH_ARGS=()
if [[ -s /run/secrets/GITHUB_TOKEN ]]; then
	CURL_AUTH_ARGS=(-H "Authorization: Bearer $(cat /run/secrets/GITHUB_TOKEN)")
fi

###############################################################################
# Desktop (RPM)
###############################################################################
echo "Installing Bitwarden Desktop..."

API_URL="https://api.github.com/repos/bitwarden/desktop/releases/latest"

echo "Resolving latest Bitwarden Desktop release from ${API_URL} ..."
curl -fsSL "${CURL_AUTH_ARGS[@]}" "${API_URL}" -o "${WORKDIR}/release.json"

# Prefer python3 (always in base) over jq (not guaranteed in build container).
RPM_URL="$(python3 -c "
import json, re, sys
pattern = re.compile(sys.argv[1])
with open('${WORKDIR}/release.json') as f:
    data = json.load(f)
for asset in data.get('assets', []):
    url = asset.get('browser_download_url', '')
    if pattern.search(url):
        print(url)
        break
" "${RPM_PATTERN}")"

if [[ -z "${RPM_URL:-}" ]]; then
	echo "ERROR: no Bitwarden RPM matching ${RPM_PATTERN} found in latest release" >&2
	exit 1
fi

# Try to find a sibling checksum asset for the RPM (best-effort: naming varies).
CHECKSUM_URL="$(python3 -c "
import json, sys
with open('${WORKDIR}/release.json') as f:
    data = json.load(f)
for asset in data.get('assets', []):
    name = asset.get('name', '')
    lower = name.lower()
    if 'rpm' in lower and ('sha256' in lower or 'sha512' in lower or 'checksum' in lower):
        print(asset.get('browser_download_url', ''))
        break
" || true)"

echo "Downloading ${RPM_URL} ..."
curl -fSL "${RPM_URL}" -o "${WORKDIR}/bitwarden.rpm"

echo "Verifying Desktop download..."
if [[ -n "${CHECKSUM_URL:-}" ]]; then
	echo "Found checksum asset: ${CHECKSUM_URL}"
	curl -fsSL "${CHECKSUM_URL}" -o "${WORKDIR}/checksum.txt"
	# Checksum files sometimes contain '<hash>  <filename>'; normalize to our file.
	if grep -qE '[a-fA-F0-9]{64,}' "${WORKDIR}/checksum.txt"; then
		EXPECTED="$(grep -oE '[a-fA-F0-9]{64,}' "${WORKDIR}/checksum.txt" | head -n1)"
		echo "${EXPECTED}  ${WORKDIR}/bitwarden.rpm" | sha256sum -c -
	else
		echo "WARNING: checksum file format unrecognized, falling back to rpm -K" >&2
		rpm -K "${WORKDIR}/bitwarden.rpm"
	fi
else
	echo "No checksum asset published; verifying embedded RPM digests..."
	rpm -K "${WORKDIR}/bitwarden.rpm"
fi

echo "Installing Bitwarden RPM..."
dnf5 install -y "${WORKDIR}/bitwarden.rpm"

###############################################################################
# CLI (bw binary from zip)
###############################################################################
echo "Installing Bitwarden CLI..."

CLI_API_URL="https://api.github.com/repos/bitwarden/cli/releases/latest"

echo "Resolving latest Bitwarden CLI release from ${CLI_API_URL} ..."
curl -fsSL "${CURL_AUTH_ARGS[@]}" "${CLI_API_URL}" -o "${WORKDIR}/cli-release.json"

CLI_ZIP_URL="$(python3 -c "
import json, re
with open('${WORKDIR}/cli-release.json') as f:
    data = json.load(f)
for asset in data.get('assets', []):
    url = asset.get('browser_download_url', '')
    name = asset.get('name', '')
    if re.search(r'bw-linux-.*\.zip\$', url) and 'sha' not in name.lower():
        print(url)
        break
")"

if [[ -z "${CLI_ZIP_URL:-}" ]]; then
	echo "ERROR: no bw-linux zip found in latest bitwarden/cli release" >&2
	exit 1
fi

CLI_CHECKSUM_URL="$(python3 -c "
import json
with open('${WORKDIR}/cli-release.json') as f:
    data = json.load(f)
for asset in data.get('assets', []):
    name = asset.get('name', '').lower()
    if name.startswith('bw-linux-sha256') and name.endswith('.txt'):
        print(asset.get('browser_download_url', ''))
        break
" || true)"

echo "Downloading ${CLI_ZIP_URL} ..."
curl -fSL "${CLI_ZIP_URL}" -o "${WORKDIR}/bw-cli.zip"

echo "Verifying CLI download..."
if [[ -n "${CLI_CHECKSUM_URL:-}" ]]; then
	echo "Found CLI checksum asset: ${CLI_CHECKSUM_URL}"
	curl -fsSL "${CLI_CHECKSUM_URL}" -o "${WORKDIR}/bw-checksum.txt"
	EXPECTED="$(grep -oE '[a-fA-F0-9]{64}' "${WORKDIR}/bw-checksum.txt" | head -n1)"
	if [[ -z "${EXPECTED:-}" ]]; then
		echo "ERROR: could not parse hash from ${CLI_CHECKSUM_URL}" >&2
		exit 1
	fi
	echo "${EXPECTED}  ${WORKDIR}/bw-cli.zip" | sha256sum -c -
else
	echo "WARNING: no CLI checksum asset published; skipping hash check" >&2
fi

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

echo "Bitwarden Desktop + CLI installation completed successfully!"
# WORKDIR removed by EXIT trap (isolate + clean up: no repo file, no tmp files).
