#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

SWARM_DIR="$ROOT_DIR/swarm/stacks"
COMPOSE_DIR="$ROOT_DIR/compose"
OUTPUT="$SCRIPT_DIR/resources.toml"

SERVER="asteri-is"
SWARM="asteri"

GIT_PROVIDER="github.com"
GIT_ACCOUNT="gmnds"
REPO="gmnds/docker-infra"
BRANCH="main"

: > "$OUTPUT"

generate_stack() {
    local dir="$1"
    local target_type="$2"
    local target="$3"

    local name
    name="$(basename "$dir")"

    local files=()

    # Arquivo principal preferencial
    if [ -f "$dir/stack.yaml" ]; then
        files=("stack.yaml")
    elif [ -f "$dir/stack.yml" ]; then
        files=("stack.yml")
    elif [ -f "$dir/compose.yaml" ]; then
        files=("compose.yaml")
    elif [ -f "$dir/compose.yml" ]; then
        files=("compose.yml")
    else
        # Ex.: Chatwoot com múltiplos YAMLs
        while IFS= read -r file; do
            files+=("$(basename "$file")")
        done < <(
            find "$dir" -maxdepth 1 -type f \
                \( -name '*.yaml' -o -name '*.yml' \) \
                | sort
        )
    fi

    [ "${#files[@]}" -gt 0 ] || return

    printf '[[stack]]\n' >> "$OUTPUT"
    printf 'name = "%s"\n' "$name" >> "$OUTPUT"
    printf '[stack.config]\n' >> "$OUTPUT"

    if [ "$target_type" = "server" ]; then
        printf 'server = "%s"\n' "$target" >> "$OUTPUT"
    else
        printf 'swarm = "%s"\n' "$target" >> "$OUTPUT"
    fi

    printf 'git_provider = "%s"\n' "$GIT_PROVIDER" >> "$OUTPUT"
    printf 'git_account = "%s"\n' "$GIT_ACCOUNT" >> "$OUTPUT"
    printf 'repo = "%s"\n' "$REPO" >> "$OUTPUT"
    printf 'branch = "%s"\n' "$BRANCH" >> "$OUTPUT"
    local relative_dir="${dir#"$ROOT_DIR"/}"
    printf 'run_directory = "%s"\n' "$relative_dir" >> "$OUTPUT"

    printf 'file_paths = [' >> "$OUTPUT"

    local first=true
    for file in "${files[@]}"; do
        if "$first"; then
            first=false
        else
            printf ', ' >> "$OUTPUT"
        fi

        printf '"%s"' "$file" >> "$OUTPUT"
    done

    printf ']\n\n' >> "$OUTPUT"
}


#
# Docker Compose
#
for dir in "$COMPOSE_DIR"/*; do
    [ -d "$dir" ] || continue

    name="$(basename "$dir")"

    # Komodo é bootstrap, não gerencia a si mesmo
    if [ "$name" = "komodo" ]; then
        continue
    fi

    generate_stack "$dir" "server" "$SERVER"
done


#
# Docker Swarm
#
for dir in "$SWARM_DIR"/*; do
    [ -d "$dir" ] || continue

    generate_stack "$dir" "swarm" "$SWARM"
done

echo "Gerado: $OUTPUT"
