# Modelo de stack para Docker Swarm

Copie a pasta e renomeie os identificadores genéricos antes de usar:

```bash
cp -R templates/stack swarm/stacks/minha_app
cd swarm/stacks/minha_app
cp .env.example .env
```

Edite `.env` e carregue suas variáveis no shell. O `docker stack deploy` não
deve depender do carregamento automático do arquivo:

```bash
set -a
. ./.env
set +a
```

Crie o volume, a rede e o secret externos antes do primeiro deploy:

```bash
docker volume create "${STACK_NAME}_data"
docker network create --driver overlay --attachable traefik_proxy
openssl rand -hex 32 | docker secret create app_secret -
```

Se a rede ou o secret já existirem, não os recrie. Renomeie `app_secret` para
um nome exclusivo da aplicação, como `minha_app_api_key`.

Valide e publique:

```bash
docker stack config -c stack.yaml >/dev/null
docker stack deploy --prune -c stack.yaml "$STACK_NAME"
```

## Checklist antes de versionar

- Use imagem com versão fixa ou digest.
- Mantenha senhas, tokens e chaves em Docker Secrets.
- Confirme que `.env` está ignorado e versione somente `.env.example`.
- Não publique portas diretamente quando o acesso puder passar pelo Traefik.
- Use volumes externos apenas quando os dados precisarem sobreviver à remoção da stack.
- Confirme se a imagem realmente aceita variáveis `*_FILE`; caso contrário,
  adapte o entrypoint para ler `/run/secrets`.
- Restrinja o Docker Socket ou use um socket proxy quando ele for indispensável.
