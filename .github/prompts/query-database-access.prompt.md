---
description: Identifica quais microserviços gravam ou lêem em uma base de dados específica.
---

Identifique todos os microserviços no workspace que acessam a base de dados "${{database_name}}".

Para cada serviço encontrado, determine:
1. Se realiza operações de leitura (SELECT, find, get).
2. Se realiza operações de escrita (INSERT, UPDATE, DELETE, save, persist, upsert).
3. Qual é o repository/DAO responsável.
4. Qual é a connection string ou datasource configurada.

Apresente os resultados em formato tabular:

| Serviço | Tipo de Acesso | Repository/DAO | Arquivo | Evidência |
| :--- | :--- | :--- | :--- | :--- |

Inclua apenas resultados com evidências concretas no código-fonte.
