# TG

## Estrutura dos Arquivos na VM Linux

```
netbox-docker/
│
├── docker-compose.yml
├── docker-compose.override.yml   
├── Dockerfile_Plugins           
├── plugin_requirements.txt
│
└── netbox/
    └── plugins.py
```

## Comandos para subir/derrubar os containers

Subir

```
docker-compose up -d 
```

Derrubar

```
docker-compose down 
```
