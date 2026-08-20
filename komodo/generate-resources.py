#!/usr/bin/env python3

from pathlib import Path

import tomlkit
from tomlkit import aot, document, string, table


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent

SWARM_DIR = ROOT_DIR / "swarm" / "stacks"
COMPOSE_DIR = ROOT_DIR / "compose"

ENV_FILE = ROOT_DIR / "docker.env.example"
OUTPUT = SCRIPT_DIR / "resources.toml"

SERVER = "asteri-is"
SWARM = "asteri"

GIT_PROVIDER = "github.com"
GIT_ACCOUNT = "gmnds"
REPO = "gmnds/docker-infra"
BRANCH = "main"

# Existem no Komodo, mas não sobem automaticamente.
NO_AUTO_DEPLOY = {
    "portainer",
}


def load_env(path: Path) -> dict[str, str]:
    if not path.exists():
        raise SystemExit(f"Erro: arquivo não encontrado: {path}")

    env: dict[str, str] = {}

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#"):
            continue

        if line.startswith("export "):
            line = line[7:].strip()

        if "=" not in line:
            raise SystemExit(
                f"Erro em {path}: linha inválida:\n  {raw_line}"
            )

        key, value = line.split("=", 1)

        key = key.strip()
        value = value.strip()

        if (
            len(value) >= 2
            and value[0] == value[-1]
            and value[0] in ('"', "'")
        ):
            value = value[1:-1]

        env[key] = value

    return env


def validate_env(env: dict[str, str]) -> None:
    docker_root = env.get("DOCKER_ROOT")

    if not docker_root:
        raise SystemExit(
            f"Erro: DOCKER_ROOT não está definido em {ENV_FILE}"
        )

    if docker_root.rstrip("/").endswith("/volumes"):
        raise SystemExit(
            "Erro: DOCKER_ROOT deve apontar para a raiz Docker.\n"
            f"Atual: {docker_root}\n"
            "Esperado: /srv/docker"
        )


def load_document():
    if not OUTPUT.exists():
        return document()

    return tomlkit.parse(OUTPUT.read_text())


def ensure_aot(doc, key: str):
    if key not in doc:
        doc[key] = aot()

    return doc[key]


def existing_names(resources) -> set[str]:
    return {
        resource.get("name")
        for resource in resources
        if resource.get("name")
    }


def find_stack_files(directory: Path) -> list[str]:
    preferred = (
        "stack.yaml",
        "stack.yml",
        "compose.yaml",
        "compose.yml",
    )

    for filename in preferred:
        if (directory / filename).is_file():
            return [filename]

    return sorted(
        file.name
        for file in directory.iterdir()
        if file.is_file()
        and file.suffix in {".yaml", ".yml"}
    )


def build_environment(env: dict[str, str]):
    contents = "".join(
        f"{key}=[[{key}]]\n"
        for key in env
    )

    return string(contents, multiline=True)


def add_missing_variables(
    doc,
    env: dict[str, str],
) -> bool:
    variables = ensure_aot(doc, "variable")
    names = existing_names(variables)

    changed = False

    for key, value in env.items():
        if key in names:
            print(f"Mantendo variável: {key}")
            continue

        resource = table()
        resource.add("name", key)
        resource.add("value", value)

        variables.append(resource)

        print(f"Adicionando variável: {key}")
        changed = True

    return changed


def add_stack(
    stacks,
    existing: set[str],
    directory: Path,
    target_type: str,
    target: str,
    env: dict[str, str],
) -> bool:
    name = directory.name

    # Fundamental:
    # uma stack existente pertence ao Komodo.
    # O script não altera nada nela.
    if name in existing:
        print(f"Mantendo stack: {name}")
        return False

    files = find_stack_files(directory)

    if not files:
        print(
            f"Ignorando {directory}: nenhum YAML/YML encontrado"
        )
        return False

    relative_dir = directory.relative_to(ROOT_DIR).as_posix()

    resource = table()
    resource.add("name", name)
    resource.add(
        "deploy",
        name not in NO_AUTO_DEPLOY,
    )

    config = table()

    if target_type == "server":
        config.add("server", target)
    elif target_type == "swarm":
        config.add("swarm", target)
    else:
        raise ValueError(
            f"Target inválido: {target_type}"
        )

    config.add("git_provider", GIT_PROVIDER)
    config.add("git_account", GIT_ACCOUNT)
    config.add("repo", REPO)
    config.add("branch", BRANCH)
    config.add("run_directory", relative_dir)
    config.add("file_paths", files)
    config.add(
        "environment",
        build_environment(env),
    )

    resource.add("config", config)
    stacks.append(resource)

    existing.add(name)

    print(f"Adicionando stack: {name}")
    return True


def main() -> None:
    env = load_env(ENV_FILE)
    validate_env(env)

    doc = load_document()

    changed = add_missing_variables(doc, env)

    stacks = ensure_aot(doc, "stack")
    existing = existing_names(stacks)

    #
    # Docker Compose
    #
    if COMPOSE_DIR.exists():
        for directory in sorted(COMPOSE_DIR.iterdir()):
            if not directory.is_dir():
                continue

            # Bootstrap: Komodo não gerencia a si mesmo.
            if directory.name == "komodo":
                continue

            changed |= add_stack(
                stacks=stacks,
                existing=existing,
                directory=directory,
                target_type="server",
                target=SERVER,
                env=env,
            )

    #
    # Docker Swarm
    #
    if SWARM_DIR.exists():
        for directory in sorted(SWARM_DIR.iterdir()):
            if not directory.is_dir():
                continue

            changed |= add_stack(
                stacks=stacks,
                existing=existing,
                directory=directory,
                target_type="swarm",
                target=SWARM,
                env=env,
            )

    if not changed:
        print("\nNenhuma alteração necessária.")
        return

    OUTPUT.write_text(tomlkit.dumps(doc))

    print(f"\nAtualizado: {OUTPUT}")


if __name__ == "__main__":
    main()
