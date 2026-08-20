## Redes iniciais
```
docker network create \
  --driver overlay \
  --attachable \
  traefik_proxy
```
```
docker network create \
  --driver overlay \
  --attachable \
  dokploy-network
```
