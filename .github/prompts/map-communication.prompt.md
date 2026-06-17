---
description: Mapeia a comunicação e dependências entre todos os microserviços do workspace.
---

Na raiz ${{workspace_path}}, descubra relações entre microserviços.

Procure:
- URLs internas
- nomes de serviços em variáveis de ambiente
- clients Feign, WebClient, RestTemplate, Axios, fetch, gRPC, protobuf
- tópicos Kafka/RabbitMQ/SQS/PubSub
- consumers/producers
- OpenAPI clients
- Helm values
- Kubernetes Service/Ingress
- docker-compose service names

Gere uma matriz:
origem | destino | protocolo | evidência | criticidade | observações

Diferencie dependência confirmada de dependência provável.
