#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_directory="$repository_root/target/verification-tools"
mkdir -p "$tool_directory"

download_verified() {
  local name="$1"
  local url="$2"
  local expected_sha256="$3"
  local destination="$tool_directory/$name"
  local candidate="$destination.download"

  if [[ -f "$destination" ]]; then
    local installed_sha256
    installed_sha256="$(sha256sum "$destination")"
    installed_sha256="${installed_sha256%% *}"
    if [[ "$installed_sha256" == "$expected_sha256" ]]; then
      return
    fi
  fi

  curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 \
    "$url" --output "$candidate"
  local candidate_sha256
  candidate_sha256="$(sha256sum "$candidate")"
  candidate_sha256="${candidate_sha256%% *}"
  if [[ "$candidate_sha256" != "$expected_sha256" ]]; then
    printf 'checksum mismatch for %s\nexpected %s\nactual   %s\n' \
      "$name" "$expected_sha256" "$candidate_sha256" >&2
    exit 1
  fi
  mv "$candidate" "$destination"
}

download_verified \
  plantuml-1.2026.5.jar \
  https://github.com/plantuml/plantuml/releases/download/v1.2026.5/plantuml.jar \
  de65ffc34b5c7fdad4e86309ce2dcceff98778799ae17b93a8f492d7a69080e1

download_verified \
  batik-all-1.19.jar \
  https://repo.maven.apache.org/maven2/org/apache/xmlgraphics/batik-all/1.19/batik-all-1.19.jar \
  5dc32d73d586b12b6c4a545b83eb537e5e3c2cd820a873730b073b2e94dcf525

download_verified \
  xmlgraphics-commons-2.11.jar \
  https://repo.maven.apache.org/maven2/org/apache/xmlgraphics/xmlgraphics-commons/2.11/xmlgraphics-commons-2.11.jar \
  1a37948ebfedab0cd292cfc5007e65c2fa16a701b94c206152720d3a738561bc

download_verified \
  xml-apis-1.4.01.jar \
  https://repo.maven.apache.org/maven2/xml-apis/xml-apis/1.4.01/xml-apis-1.4.01.jar \
  a840968176645684bb01aed376e067ab39614885f9eee44abe35a5f20ebe7fad

download_verified \
  xml-apis-ext-1.3.04.jar \
  https://repo.maven.apache.org/maven2/xml-apis/xml-apis-ext/1.3.04/xml-apis-ext-1.3.04.jar \
  d0b4887dc34d57de49074a58affad439a013d0baffa1a8034f8ef2a5ea191646

download_verified \
  vinary-doc-lint-0.1.1-linux-x86_64 \
  https://github.com/vinary-tree/vinary-doc-lint/releases/download/v0.1.1/vinary-doc-lint-linux-x86_64 \
  b62e99f5935ac0a24c89d96141a19182999941afe6536c6f225176d1d959a866
chmod +x "$tool_directory/vinary-doc-lint-0.1.1-linux-x86_64"

download_verified \
  actionlint-1.7.12-linux-amd64.tar.gz \
  https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz \
  8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
tar --extract --gzip \
  --file "$tool_directory/actionlint-1.7.12-linux-amd64.tar.gz" \
  --directory "$tool_directory" actionlint
chmod +x "$tool_directory/actionlint"

download_verified \
  shellcheck-v0.11.0.linux.x86_64.tar.xz \
  https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz \
  8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
tar --extract --xz --strip-components=1 \
  --file "$tool_directory/shellcheck-v0.11.0.linux.x86_64.tar.xz" \
  --directory "$tool_directory" shellcheck-v0.11.0/shellcheck
chmod +x "$tool_directory/shellcheck"

"$tool_directory/vinary-doc-lint-0.1.1-linux-x86_64" --version
"$tool_directory/actionlint" -version
"$tool_directory/shellcheck" --version
