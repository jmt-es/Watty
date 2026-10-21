#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

REPOSITORY="${GITHUB_REPOSITORY:-$DEFAULT_REPOSITORY}"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/build/release"
FORMULA_PATH="Formula/$CLI_COMMAND.rb"
UNIVERSAL_ARCHS=(arm64 x86_64)
EXPECTED_TAG=""
TAP_DIR=""
TARBALL_SOURCE=""
HOST_ARCH_ONLY=0
ALLOW_DIRTY=0
WORK_DIR=""

usage() {
  cat <<USAGE
Usage: scripts/release.sh [options]

Builds a universal $APP_NAME.app, zips it into dist/ and writes its SHA-256
sum and the release notes next to it.

  --tag TAG             fail unless TAG is v$APP_VERSION (the version in WattyVersion.swift)
  --tap DIR             also update url and sha256 in DIR/$FORMULA_PATH from the
                        GitHub tag tarball; push the tag before running this
  --tarball-source URL  download the tarball from URL instead of GitHub (testing)
  --host-arch-only      build for this Mac's architecture only
  --allow-dirty         do not require a clean git working tree
  -h, --help            show this help
USAGE
}

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)
        [[ $# -ge 2 ]] || die "--tag needs a value"
        EXPECTED_TAG="$2"
        shift 2
        ;;
      --tap)
        [[ $# -ge 2 ]] || die "--tap needs a directory"
        TAP_DIR="$2"
        shift 2
        ;;
      --tarball-source)
        [[ $# -ge 2 ]] || die "--tarball-source needs a URL"
        TARBALL_SOURCE="$2"
        shift 2
        ;;
      --host-arch-only)
        HOST_ARCH_ONLY=1
        shift
        ;;
      --allow-dirty)
        ALLOW_DIRTY=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown argument: $1"
        ;;
    esac
  done
}

check_release_state() {
  if [[ -n "$EXPECTED_TAG" && "$EXPECTED_TAG" != "v$APP_VERSION" ]]; then
    die "Tag $EXPECTED_TAG does not match version $APP_VERSION in WattyVersion.swift (expected v$APP_VERSION)"
  fi
  git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 0

  local tag_commit head_commit
  if tag_commit="$(git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/v$APP_VERSION^{commit}")"; then
    head_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
    [[ "$tag_commit" == "$head_commit" ]] ||
      die "Tag v$APP_VERSION points at ${tag_commit:0:7} but HEAD is ${head_commit:0:7}; check out the tag first"
  fi
  if [[ "$ALLOW_DIRTY" == "0" && -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    die "The git working tree has uncommitted changes; commit them or pass --allow-dirty"
  fi
}

package_app() {
  local zip_path="$1" arch arch_flags=()
  if [[ "$HOST_ARCH_ONLY" == "0" ]]; then
    for arch in "${UNIVERSAL_ARCHS[@]}"; do
      arch_flags+=(--arch "$arch")
    done
  fi

  "$SCRIPT_DIR/build-app.sh" --output-dir "$STAGING_DIR" ${arch_flags[@]+"${arch_flags[@]}"}

  log "Creating $(basename "$zip_path")"
  rm -f "$zip_path" "$zip_path.sha256"
  ditto -c -k --keepParent "$STAGING_DIR/$APP_NAME.app" "$zip_path"
  (cd "$DIST_DIR" && shasum -a 256 "$(basename "$zip_path")" >"$(basename "$zip_path").sha256")
}

verify_zip() {
  local zip_path="$1" extract_dir="$WORK_DIR/zip-check"
  mkdir -p "$extract_dir"
  ditto -x -k "$zip_path" "$extract_dir"
  codesign --verify --deep --strict "$extract_dir/$APP_NAME.app" ||
    die "The signature of the app extracted from $(basename "$zip_path") is not valid"
}

formula_url() {
  printf 'https://github.com/%s/archive/refs/tags/v%s.tar.gz' "$REPOSITORY" "$APP_VERSION"
}

update_formula() {
  local formula="$TAP_DIR/$FORMULA_PATH" url download_url tarball checksum
  [[ -f "$formula" ]] || die "Formula not found: $formula"

  url="$(formula_url)"
  download_url="${TARBALL_SOURCE:-$url}"
  tarball="$WORK_DIR/source.tar.gz"
  log "Downloading $download_url"
  curl --fail --location --silent --show-error --output "$tarball" "$download_url" ||
    die "Could not download $download_url; push the tag v$APP_VERSION to GitHub first"
  checksum="$(shasum -a 256 "$tarball" | awk '{ print $1 }')"

  FORMULA_URL="$url" FORMULA_SHA256="$checksum" perl -0pi -e '
    s{^(  url ")[^"]*(")}{$1$ENV{FORMULA_URL}$2}m or die "no url line in formula\n";
    s{^(  sha256 ")[0-9a-f]{64}(")}{$1$ENV{FORMULA_SHA256}$2}m or die "no sha256 line in formula\n";
  ' "$formula"

  log "Updated $formula"
  log "  url    $url"
  log "  sha256 $checksum"
  log "Review, commit and push the tap to publish $APP_VERSION"
}

main() {
  parse_args "$@"
  require_macos
  require_commands ditto shasum codesign curl perl git
  check_release_state

  mkdir -p "$DIST_DIR"
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/watty-release.XXXXXX")"
  trap cleanup EXIT

  local zip_path="$DIST_DIR/$APP_NAME-$APP_VERSION-macos.zip"
  "$SCRIPT_DIR/release-notes.sh" "$APP_VERSION" >"$DIST_DIR/release-notes.md"
  package_app "$zip_path"
  verify_zip "$zip_path"

  log "Release $APP_VERSION is ready in $DIST_DIR"
  log "  $(cat "$zip_path.sha256")"
  [[ -z "$TAP_DIR" ]] || update_formula
}

main "$@"
