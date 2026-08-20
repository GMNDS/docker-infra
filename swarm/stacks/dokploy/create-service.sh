#!/usr/bin/env bash
set -e

# =====================================================
# Bootstrap yq
# =====================================================
install_yq() {
  echo "yq não encontrado, instalando..."

  if command -v snap >/dev/null; then
    sudo snap install yq
  else
    sudo wget -qO /usr/local/bin/yq \
      https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    sudo chmod +x /usr/local/bin/yq
  fi
}

command -v yq >/dev/null || install_yq

# =====================================================
# Args
# =====================================================
FILE="$1"
SERVICE=""
ALL="false"
APPLY="false"

shift || true

for arg in "$@"; do
  case "$arg" in
    --all|-all) ALL="true" ;;
    --apply)   APPLY="true" ;;
    *)         SERVICE="$arg" ;;
  esac
done

if [[ -z "$FILE" ]]; then
  echo "Uso:"
  echo "  $0 stack.yml dokploy [--apply]"
  echo "  $0 stack.yml --all [--apply]"
  exit 1
fi

if [[ "$ALL" != "true" && -z "$SERVICE" ]]; then
  echo "❌ Informe um service ou use --all"
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  echo "❌ Arquivo não encontrado: $FILE"
  exit 1
fi

# =====================================================
# Função principal
# =====================================================
generate_service() {
  local SERVICE="$1"

  IMAGE=$(yq -r ".services.$SERVICE.image // \"\"" "$FILE")
  [[ -z "$IMAGE" ]] && return

  REPLICAS=$(yq -r ".services.$SERVICE.deploy.replicas // 1" "$FILE")

  CMD="docker service create \\"
  CMD+="
  --name $SERVICE \\"
  CMD+="
  --replicas $REPLICAS \\"

  # ---------------- Networks ----------------
  while read -r net; do
    [[ -z "$net" ]] && continue
    CMD+="
  --network $net \\"
  done < <(
    yq -r "
      .services.$SERVICE.networks
      | select(type == \"!!seq\")
      | .[]
    " "$FILE"
  )

  while read -r net; do
    [[ -z "$net" ]] && continue
    CMD+="
  --network $net \\"
  done < <(
    yq -r "
      .services.$SERVICE.networks
      | select(type == \"!!map\")
      | keys[]
    " "$FILE"
  )

  # ---------------- Constraints ----------------
  while read -r c; do
    [[ -z "$c" ]] && continue
    CMD+="
  --constraint '$c' \\"
  done < <(
    yq -r "
      .services.$SERVICE.deploy.placement.constraints
      | select(type == \"!!seq\")
      | .[]
    " "$FILE"
  )

  # ---------------- Environment ----------------
  while read -r env; do
    [[ -z "$env" ]] && continue
    [[ "$env" == "=" ]] && continue
    CMD+="
  --env '$env' \\"
  done < <(
    yq -r "
      .services.$SERVICE.environment
      | select(type == \"!!map\")
      | to_entries[]
      | \"\(.key)=\(.value)\"
    " "$FILE"
  )

  # ---------------- Volumes ----------------
  while read -r vol; do
    [[ -z "$vol" ]] && continue

    SRC="${vol%%:*}"
    DST="${vol##*:}"

    if [[ "$SRC" == /* ]]; then
      CMD+="
  --mount type=bind,source=$SRC,target=$DST \\"
    else
      CMD+="
  --mount type=volume,source=$SRC,target=$DST \\"
    fi
  done < <(
    yq -r "
      .services.$SERVICE.volumes
      | select(type == \"!!seq\")
      | .[]
    " "$FILE"
  )

  # ---------------- Ports (long) ----------------
  while IFS="|" read -r pub tar mode; do
    [[ -z "$pub" || -z "$tar" ]] && continue

    if [[ -n "$mode" ]]; then
      CMD+="
  --publish published=$pub,target=$tar,mode=$mode \\"
    else
      CMD+="
  --publish published=$pub,target=$tar \\"
    fi
  done < <(
    yq -r "
      .services.$SERVICE.ports
      | select(type == \"!!seq\")
      | .[]
      | select(type == \"!!map\")
      | select(.published != null and .target != null)
      | \"\(.published)|\(.target)|\(.mode // \\\"\\\")\"
    " "$FILE"
  )

  # ---------------- Ports (short) ----------------
  while read -r port; do
    [[ -z "$port" ]] && continue
    [[ "$port" != *:* ]] && continue

    CMD+="
  --publish published=${port%%:*},target=${port##*:} \\"
  done < <(
    yq -r "
      .services.$SERVICE.ports
      | select(type == \"!!seq\")
      | .[]
      | select(type == \"!!str\")
    " "$FILE"
  )

  # ---------------- Secrets ----------------
  while read -r sec; do
    [[ -z "$sec" ]] && continue
    CMD+="
  --secret $sec \\"
  done < <(
    yq -r "
      .services.$SERVICE.secrets
      | select(type == \"!!seq\")
      | .[]
    " "$FILE"
  )

  # ---------------- Labels ----------------
  while read -r label; do
    [[ -z "$label" ]] && continue
    [[ "$label" == "=" ]] && continue
    CMD+="
  --label '$label' \\"
  done < <(
    yq -r "
      .services.$SERVICE.deploy.labels
      | select(type == \"!!map\")
      | to_entries[]
      | \"\(.key)=\(.value)\"
    " "$FILE"
  )

  # ---------------- Image ----------------
  CMD+="
  $IMAGE"

  echo
  echo "### Service: $SERVICE ###"
  echo
  echo "$CMD"

  if [[ "$APPLY" == "true" ]]; then
    echo
    echo ">>> Aplicando service $SERVICE"
    eval "$CMD"
  fi
}

# =====================================================
# Execução
# =====================================================
if [[ "$ALL" == "true" ]]; then
  SERVICES=$(yq -r '.services | keys | .[]' "$FILE")
else
  SERVICES="$SERVICE"
fi

for svc in $SERVICES; do
  generate_service "$svc"
done
