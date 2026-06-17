---
description: Identifica quais serviços dependem de um contrato OpenAPI específico.
---

Quais serviços dependem do contrato OpenAPI "${{contract_name}}"?

Analise o workspace e identifique:

1. Quais serviços são **provedores** (implementam os endpoints definidos no contrato).
2. Quais serviços são **consumidores** (utilizam clientes gerados a partir do contrato).
3. Quais operações específicas do contrato são utilizadas por cada consumidor.
4. Se existem versões diferentes do contrato em uso simultaneamente.

Procure por:
- Arquivos OpenAPI/Swagger (.yaml, .json) com o nome do contrato.
- Clientes gerados (Feign interfaces, WebClient builders, RestTemplate calls).
- Referências em build files (pom.xml, build.gradle) a plugins de geração de código OpenAPI.
- Imports de pacotes gerados automaticamente.

Apresente os resultados em formato tabular:

| Serviço | Papel (Provedor/Consumidor) | Operações Utilizadas | Versão do Contrato | Arquivo de Evidência |
| :--- | :--- | :--- | :--- | :--- |
