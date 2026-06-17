---
description: Analisa o fluxo arquitetural de ponta a ponta de um microserviço específico usando RAG + Serena.
---

Ative o projeto do serviço ${{service_name}} com Serena.

Analise o fluxo arquitetural de ponta a ponta:
- endpoints de entrada
- controllers/handlers
- services/use cases
- repositories/DAOs
- chamadas HTTP/gRPC externas
- publicação ou consumo de mensagens
- acesso a banco
- tratamento de erro
- autenticação/autorização
- observabilidade

## Estratégia de Análise

1. Use `activate_project` do Serena para ativar o projeto.
2. Use `get_symbol_overview` para obter o outline dos arquivos principais.
3. Use `find_symbol` para localizar controllers, services e repositories.
4. Use `find_referencing_symbols` para rastrear dependências entre camadas.
5. Use `find_implementations` para encontrar implementações concretas de interfaces.
6. Complemente com busca RAG vetorial para conceitos em linguagem natural.

Retorne uma explicação com evidências por arquivo e símbolo.
Não faça alterações.
