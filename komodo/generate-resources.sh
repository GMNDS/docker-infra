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

# Resources que devem existir no Komodo,
# mas não devem ser deployados automaticamente.
NO_AUTO_DEPLOY=(
    "portainer"
)

: > "$OUTPUT"

should_auto_deploy() {
    local name="$1"

    for excluded in "${NO_AUTO_DEPLOY[@]}"; do
        if [ "$name" = "$excluded" ]; then
            return 1
        fi
    done

    return 0
}

find_stack_files() {
    local dir="$1"
    local -n result="$2"

    result=()

    # Arquivo principal preferencial
    if [ -f "$dir/stack.yaml" ]; then
        result=("stack.yaml")
        return
    fi

    if [ -f "$dir/stack.yml" ]; then
        result=("stack.yml")
        return
    fi

    if [ -f "$dir/compose.yaml" ]; then
        result=("compose.yaml")
        return
    fi

    if [ -f "$dir/compose.yml" ]; then
        result=("compose.yml")
        return
    fi

    # Caso como Chatwoot: múltiplos YAML/YML
    while IFS= read -r file; do
        result+=("$(basename "$file")")
    done < <(
        find "$dir" \
            -maxdepth 1 \
            -type f \
            \( -name '*.yaml' -o -name '*.yml' \) \
            | sort
    )
}

generate_stack() {
    local dir="$1"
    local target_type="$2"
    local target="$3"

    local name
    local relative_dir
    local files=()

    name="$(basename "$dir")"
    relative_dir="${dir#"$ROOT_DIR"/}"

    find_stack_files "$dir" files

    # Ignora diretórios sem YAML/YML
    if [ "${#files[@]}" -eq 0 ]; then
        echo "Ignorando '$relative_dir': nenhum YAML/YML encontrado." >&2
        return
    fi

    printf '[[stack]]\n' >> "$OUTPUT"
    printf 'name = "%s"\n' "$name" >> "$OUTPUT"

    if should_auto_deploy "$name"; then
        printf 'deploy = true\n' >> "$OUTPUT"
    else
        printf 'deploy = false\n' >> "$OUTPUT"
    fi

    printf '[stack.config]\n' >> "$OUTPUT"

    case "$target_type" in
        server)
            printf 'server = "%s"\n' "$target" >> "$OUTPUT"
            ;;
        swarm)
            printf 'swarm = "%s"\n' "$target" >> "$OUTPUT"
            ;;
        *)
            echo "Target inválido para '$name': $target_type" >&2
            exit 1
            ;;
    esac

    printf 'git_provider = "%s"\n' "$GIT_PROVIDER" >> "$OUTPUT"
    printf 'git_account = "%s"\n' "$GIT_ACCOUNT" >> "$OUTPUT"
    printf 'repo = "%s"\n' "$REPO" >> "$OUTPUT"
    printf 'branch = "%s"\n' "$BRANCH" >> "$OUTPUT"
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
if [ -d "$COMPOSE_DIR" ]; then
    for dir in "$COMPOSE_DIR"/*; do
        [ -d "$dir" ] || continue

        name="$(basename "$dir")"

        # Komodo é bootstrap e não gerencia a si próprio.
        if [ "$name" = "komodo" ]; then
            continue
        fi

        generate_stack "$dir" "server" "$SERVER"
    done
fi

#
# Docker Swarm
#
if [ -d "$SWARM_DIR" ]; then
    for dir in "$SWARM_DIR"/*; do
        [ -d "$dir" ] || continue

        generate_stack "$dir" "swarm" "$SWARM"
    done
fi

echo "Gerado: $OUTPUT"
