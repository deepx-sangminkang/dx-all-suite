#!/bin/bash

SCRIPT_DIR=$(realpath "$(dirname "$0")")
PROJECT_ROOT=$(realpath -s "${SCRIPT_DIR}/..")

# color env settings
source ${PROJECT_ROOT}/scripts/color_env.sh

pushd $SCRIPT_DIR

USE_BUILD=1
USE_SERVE=0

# Function to display help message
show_help() {
  echo "Usage: $(basename "$0") [--build] [--serve]"
  echo "Example: $0 --serve"
  echo "Options:"
  echo "  [--build]             Make PDF guide document file (default: on)"
  echo "  [--serve]             Make PDF guide document file and Serve Web site"
  echo "  [--help]              Show this help message"

  if [ "$1" == "error" ]; then
    echo "Error: Invalid or missing arguments."
    exit 1
  fi
  exit 0
}

check_and_install_deps() {
    local packages=(
        mkdocs
        mkdocs-material
        mkdocs-video
        pymdown-extensions
        mkdocs-to-pdf
        mkdocs-include-markdown-plugin
    )
    local missing=()

    for pkg in "${packages[@]}"; do
        if ! pip show "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${COLOR_YELLOW}Installing missing packages: ${missing[*]}${COLOR_RESET}"
        pip install "${missing[@]}" || { echo -e "${COLOR_RED}Failed to install packages. Please run 'pip install ${missing[*]}' manually.${COLOR_RESET}"; exit 1; }
    fi
}

# Remove everything main() stages for the build. Runs on any exit (EXIT trap), so a
# failed or interrupted build leaves no generated file in the source tree.
cleanup() {
    rm -f "${SCRIPT_DIR}/mkdocs.yml"
    [ -n "${AI_STUDIO_DST:-}" ] && rm -rf "$AI_STUDIO_DST"
    [ -n "${SHOWCASE_DST:-}" ] && rm -f "$SHOWCASE_DST"
    [ "${#SHOWCASE_MEDIA[@]}" -gt 0 ] && rm -f "${SHOWCASE_MEDIA[@]}"
    return 0
}
SHOWCASE_MEDIA=()

main() {
    check_and_install_deps
    trap cleanup EXIT

    VERSION=$(head -n 1 ${PROJECT_ROOT}/release.ver | tr -d '\r\n')
    echo "VERSION=${VERSION}"

    # Extract latest release date from RELEASE_NOTES.md (format: ## DX-All-Suite vX.X.X / YYYY-MM-DD)
    RELEASE_LINE=$(grep -m 1 "^## DX-All-Suite" ${PROJECT_ROOT}/RELEASE_NOTES.md)
    RAW_DATE=$(echo "$RELEASE_LINE" | awk -F' / ' '{print $2}' | tr -d '\r')
    RELEASE_DATE=$(date -d "$RAW_DATE" +%b_%Y | tr '[:lower:]' '[:upper:]')
    echo "RELEASE_DATE=${RELEASE_DATE}"

    export PDF_FILE_PATH=../DX-AS_${VERSION}_${RELEASE_DATE}.pdf
    echo "PDF_FILE_PATH=${PDF_FILE_PATH}"

    # Create a temporary yml from a template with the version
    envsubst < mkdocs-template.yml > mkdocs.yml

    unset PDF_FILE_PATH

    # Fold the DX AI Studio manual into this build. Those docs live in the sibling
    # dx-ai-studio tree (their own source of truth + standalone site); copy them into a
    # temporary source/ai-studio/ so the nav entries resolve, then remove after build.
    AI_STUDIO_SRC="${PROJECT_ROOT}/dx-ai-studio/docs/source"
    AI_STUDIO_DST="${SCRIPT_DIR}/source/ai-studio"
    rm -rf "$AI_STUDIO_DST"
    if [ -d "$AI_STUDIO_SRC" ]; then
        mkdir -p "$AI_STUDIO_DST"
        cp "$AI_STUDIO_SRC"/*.md "$AI_STUDIO_DST"/
        [ -d "$AI_STUDIO_SRC/resources" ] && cp -r "$AI_STUDIO_SRC/resources" "$AI_STUDIO_DST/resources"
    else
        echo -e "${COLOR_YELLOW}WARNING: dx-ai-studio docs not found at $AI_STUDIO_SRC — AI Studio section will be missing${COLOR_RESET}"
    fi

    # The showcase catalog (dx-agent-dev-showcase/README.md) and its media (repo-root img/)
    # live outside source/. Stage the catalog next to source/ with image paths that point
    # into source/img/, and copy the media there, so the Showcases page resolves; both are
    # removed by cleanup(). The catalog is generated (dx-showcase-gen) and always writes
    # its media as ../img/<name>, which is the only form the sed below rewrites.
    SHOWCASE_SRC="${PROJECT_ROOT}/dx-agent-dev-showcase/README.md"
    SHOWCASE_DST="${SCRIPT_DIR}/_showcase_catalog.md"
    SHOWCASE_MEDIA=()
    rm -f "$SHOWCASE_DST"
    if [ -f "$SHOWCASE_SRC" ]; then
        sed 's#\.\./img/#source/img/#g' "$SHOWCASE_SRC" > "$SHOWCASE_DST"
        for media in "${PROJECT_ROOT}"/img/dx-agent-dev-*; do
            [ -e "$media" ] || continue
            staged="${SCRIPT_DIR}/source/img/$(basename "$media")"
            [ -e "$staged" ] && continue
            cp "$media" "$staged" && SHOWCASE_MEDIA+=("$staged")
        done
    else
        echo -e "${COLOR_YELLOW}WARNING: showcase catalog not found at $SHOWCASE_SRC — Showcases page will be empty${COLOR_RESET}"
        : > "$SHOWCASE_DST"
    fi

    if [ $USE_SERVE -eq 1 ]; then
        # Run mkdocs build
        mkdocs serve
    else
        # Run mkdocs build
        mkdocs build
    fi

    # Staged files are removed by cleanup() (EXIT trap)
}

# parse args
for i in "$@"; do
    case "$1" in
        --build)
            USE_BUILD=1
            ;;
        --serve)
            USE_SERVE=1
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help "error"
            ;;
    esac
    shift
done

main

popd

exit 0
