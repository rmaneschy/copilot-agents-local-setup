---
description: Identifica onde a autenticação é validada e quais serviços ignoram autorização.
---

Onde a autenticação é validada e quais serviços ignoram autorização?

Analise todos os microserviços no workspace e:

1. Identifique o mecanismo de autenticação utilizado (JWT, OAuth2, API Key, Session, etc.).
2. Localize os filtros/interceptors de segurança (SecurityFilterChain, middleware, guards).
3. Mapeie o fluxo de validação do token (onde é verificado, qual biblioteca é usada).
4. Liste endpoints marcados como públicos (permitAll, @Anonymous, whitelist, noAuth).
5. Identifique serviços que NÃO possuem configuração de segurança explícita.

Apresente os resultados em duas tabelas:

**Tabela 1: Serviços com Autenticação Configurada**
| Serviço | Mecanismo | Filtro/Interceptor | Arquivo | Observações |

**Tabela 2: Endpoints Públicos ou Serviços sem Autorização**
| Serviço | Endpoint/Classe | Motivo (público/sem config) | Arquivo | Risco |

Classifique o risco como Alto, Médio ou Baixo com justificativa.
