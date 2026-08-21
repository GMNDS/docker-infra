# Chatwoot no Docker Swarm

Copie `.env.example` para `.env`, preencha os valores e carregue-os antes do deploy:

```bash
set -a
. ./.env
set +a
```

Crie os secrets externos uma única vez no manager do Swarm:

```bash
openssl rand -base64 48 | docker secret create chatwoot_secret_key_base -
openssl rand -base64 32 | docker secret create chatwoot_postgres_password -
read -rsp "Senha SMTP: " SMTP_SECRET && printf %s "$SMTP_SECRET" | docker secret create chatwoot_smtp_password - && unset SMTP_SECRET
```

Use a mesma senha de `chatwoot_postgres_password`, devidamente codificada para URL,
nas variáveis `EVOLUTION_DATABASE_URI` e `EVOLUTION_CHATWOOT_DATABASE_URI`.

Faça o deploy do PostgreSQL e Redis antes do Chatwoot. Execute `migrate.yml` a cada
instalação ou atualização que exigir migração e, em seguida, faça o deploy de
`chatwoot.yml`. O arquivo `ev.yml` é uma stack separada para a Evolution API.
