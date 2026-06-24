# Ollama: Tweaks, KV Cache e Perfis de Hardware

## Introdução

O desempenho de um agente autônomo de desenvolvimento depende diretamente da capacidade computacional da máquina do engenheiro. O Ollama, como motor de inferência local, oferece um conjunto de **variáveis de ambiente** (tweaks) e **parâmetros de modelo** (Modelfile) que permitem ajustar o comportamento do LLM para extrair o máximo de desempenho do hardware disponível.

Este documento detalha cada configuração, explica o mecanismo do **KV Cache**, e apresenta os três perfis de hardware (LIGHT, MEDIUM, POWER) com seus impactos práticos no dia a dia do engenheiro de software.

---

## O que é o KV Cache?

O **KV Cache** (Key-Value Cache) é a memória de trabalho do LLM durante a inferência. Quando o modelo processa um prompt, ele calcula pares de vetores **Key** e **Value** para cada token em cada camada de atenção. Esses vetores são armazenados no KV Cache para que o modelo não precise recalculá-los a cada novo token gerado.

> Em termos simples: o KV Cache é o que permite ao modelo "lembrar" do que já foi dito na conversa. Quanto maior o contexto (mais tokens), maior o KV Cache e maior o consumo de VRAM.

### Consumo de VRAM pelo KV Cache

Para um modelo de **8B parâmetros** com diferentes tamanhos de contexto:

| Tipo de KV Cache | 8K tokens | 32K tokens | 64K tokens |
| :--- | :--- | :--- | :--- |
| **f16** (padrão) | ~1.5 GB | ~6 GB | ~12 GB |
| **q8_0** (recomendado) | ~0.75 GB | ~3 GB | ~6 GB |
| **q4_0** (econômico) | ~0.5 GB | ~2 GB | ~4 GB |

### Impacto na Qualidade

| Quantização | Perplexidade Adicional | Percepção Humana |
| :--- | :--- | :--- |
| **f16** | +0.000 (referência) | Máxima qualidade |
| **q8_0** | +0.002 a +0.05 | **Imperceptível** — recomendado para produção |
| **q4_0** | +0.206 a +0.25 | Perceptível em raciocínios longos, aceitável para tarefas curtas |

### Requisitos Técnicos

A quantização do KV Cache exige que o **Flash Attention** esteja habilitado (`OLLAMA_FLASH_ATTENTION=1`). Sem Flash Attention, a variável `OLLAMA_KV_CACHE_TYPE` é ignorada silenciosamente.

---

## Variáveis de Ambiente (Server-Level)

Estas variáveis controlam o comportamento global do servidor Ollama e afetam **todos os modelos** carregados.

### Configurações de Performance

| Variável | Descrição | Padrão | Valores Possíveis |
| :--- | :--- | :--- | :--- |
| `OLLAMA_FLASH_ATTENTION` | Habilita o algoritmo Flash Attention v2, que reduz o consumo de memória e acelera a inferência em 2-3x | `off` | `1` (ativar) |
| `OLLAMA_KV_CACHE_TYPE` | Define a quantização do KV Cache. Requer Flash Attention ativo | `f16` | `f16`, `q8_0`, `q4_0` |
| `OLLAMA_CONTEXT_LENGTH` | Context window padrão para modelos que não definem `num_ctx` explicitamente | `4096` | Qualquer inteiro (ex: `8192`, `32768`, `65536`) |
| `OLLAMA_NUM_PARALLEL` | Número de requisições simultâneas que um modelo carregado pode processar | `1` | `1` a `8` (limitado pela VRAM) |

### Configurações de Memória

| Variável | Descrição | Padrão | Valores Possíveis |
| :--- | :--- | :--- | :--- |
| `OLLAMA_KEEP_ALIVE` | Tempo que o modelo permanece carregado na memória após a última requisição | `5m` | `5m`, `1h`, `-1` (permanente) |
| `OLLAMA_MAX_LOADED_MODELS` | Número máximo de modelos carregados simultaneamente na memória | `3` | `1` a `N` (limitado pela VRAM/RAM) |
| `OLLAMA_GPU_OVERHEAD` | Quantidade de VRAM (em bytes) reservada para o sistema operacional e outros processos | `0` | Ex: `1073741824` (1 GB) |
| `OLLAMA_SCHED_SPREAD` | Distribui as camadas do modelo igualmente entre múltiplas GPUs | `off` | `1` (ativar, apenas multi-GPU) |

### Configurações de Rede e Armazenamento

| Variável | Descrição | Padrão | Valores Possíveis |
| :--- | :--- | :--- | :--- |
| `OLLAMA_HOST` | Endereço e porta do servidor Ollama | `127.0.0.1:11434` | `0.0.0.0:11434` (acesso remoto) |
| `OLLAMA_MODELS` | Diretório onde os modelos são armazenados | `~/.ollama/models` | Qualquer caminho (ex: `D:\models`) |
| `OLLAMA_MAX_QUEUE` | Número máximo de requisições na fila antes de rejeitar novas | `512` | Qualquer inteiro |
| `OLLAMA_DEBUG` | Habilita logs detalhados para troubleshooting | `off` | `1` (ativar) |

---

## Parâmetros do Modelfile (Model-Level)

Estes parâmetros são definidos **por modelo** através de um `Modelfile` e controlam o comportamento de geração de texto.

### Parâmetros de Amostragem

| Parâmetro | Descrição | Padrão | Recomendação para Código |
| :--- | :--- | :--- | :--- |
| `temperature` | Controla a aleatoriedade. Valores baixos = mais determinístico, valores altos = mais criativo | `0.8` | **`0.1` a `0.3`** (código exige precisão) |
| `top_k` | Limita o número de tokens candidatos para o próximo token | `40` | **`20` a `40`** |
| `top_p` | Nucleus sampling — considera tokens cuja probabilidade acumulada atinge este valor | `0.9` | **`0.85` a `0.95`** |
| `min_p` | Probabilidade mínima relativa ao token mais provável | `0.0` | **`0.05`** (filtra tokens improváveis) |
| `repeat_penalty` | Penaliza tokens que já apareceram na janela de lookback | `1.1` | **`1.1`** (manter padrão) |
| `repeat_last_n` | Tamanho da janela de lookback para detecção de repetição | `64` | **`64`** (manter padrão) |

### Parâmetros de Controle

| Parâmetro | Descrição | Padrão | Recomendação para Código |
| :--- | :--- | :--- | :--- |
| `num_ctx` | Context window deste modelo específico (override do server-level) | `2048` | Definido pelo perfil (8K/32K/64K) |
| `num_predict` | Número máximo de tokens na resposta gerada | `-1` (infinito) | **`4096`** ou **`-1`** |
| `seed` | Semente para reprodutibilidade (0 = aleatório) | `0` | **`42`** (para testes determinísticos) |
| `stop` | Sequências que interrompem a geração | — | Depende do modelo |

### Exemplo de Modelfile para Agente de Código

```dockerfile
FROM qwen2.5-coder:7b

# Parâmetros otimizados para geração de código
PARAMETER temperature 0.2
PARAMETER top_p 0.9
PARAMETER min_p 0.05
PARAMETER num_ctx 32768
PARAMETER repeat_penalty 1.1
PARAMETER num_predict 4096

SYSTEM """Você é um assistente de engenharia de software especializado em análise
e geração de código. Siga os princípios SOLID, produza código limpo e testável.
Sempre explique suas decisões técnicas."""
```

---

## Perfis de Hardware

O script `setup.ps1` detecta automaticamente o hardware da máquina e aplica o perfil mais adequado. A detecção considera **VRAM** e **RAM** como critérios primários.

### Critérios de Classificação

| Perfil | VRAM | RAM | Detecção |
| :--- | :--- | :--- | :--- |
| **LIGHT** | < 6 GB | < 16 GB | GPU integrada, notebooks básicos |
| **MEDIUM** | 6–11 GB | 16–31 GB | RTX 3060, RTX 4060, notebooks gamer |
| **POWER** | ≥ 12 GB | ≥ 32 GB | RTX 4080, RTX 4090, workstations |

### Configurações Aplicadas por Perfil

| Variável | LIGHT | MEDIUM | POWER |
| :--- | :--- | :--- | :--- |
| `OLLAMA_FLASH_ATTENTION` | `1` | `1` | `1` |
| `OLLAMA_KV_CACHE_TYPE` | `q4_0` | `q8_0` | `q8_0` |
| `OLLAMA_CONTEXT_LENGTH` | `8192` | `32768` | `65536` |
| `OLLAMA_KEEP_ALIVE` | `5m` | `-1` | `-1` |
| `OLLAMA_NUM_PARALLEL` | `1` | `2` | `4` |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | `1` | `2` |

### Modelo de Código Recomendado por Perfil

| Perfil | Modelo | Tamanho em Disco | VRAM (modelo + KV) |
| :--- | :--- | :--- | :--- |
| **LIGHT** | `qwen2.5-coder:3b` | ~2 GB | ~2.5 GB total |
| **MEDIUM** | `qwen2.5-coder:7b` | ~4.5 GB | ~7.5 GB total |
| **POWER** | `qwen2.5-coder:14b` | ~9 GB | ~15 GB total |

---

## Impacto no Desempenho do Agente Autônomo

O agente autônomo (Copilot + MCP tools) depende do Ollama para duas operações:

1. **Embedding** — Transformar código em vetores para busca semântica (RAG)
2. **Inferência** — Gerar respostas, analisar código, produzir specs (modelo local)

### Perfil LIGHT — "O Agente Cauteloso"

**Capacidade de contexto:** ~6.000 tokens úteis (descontando overhead do sistema)

**O que o agente CONSEGUE fazer:**
- Analisar **1 a 2 arquivos por vez** (até ~200 linhas de código)
- Responder perguntas simples sobre um método ou classe
- Gerar testes unitários para funções isoladas
- Fazer embedding de código para busca semântica (embedding é operação leve)

**O que o agente NÃO consegue fazer bem:**
- Analisar dependências entre múltiplos arquivos simultaneamente
- Manter contexto de uma spec longa durante a implementação
- Executar fluxos multi-step complexos (perde contexto no meio)

**Experiência do engenheiro:**

| Métrica | Valor |
| :--- | :--- |
| Latência por resposta | 3–8 segundos |
| Cold start (após inatividade) | 5–10 segundos |
| Qualidade em tarefas curtas | Boa |
| Qualidade em tarefas longas | Degradada (esquece instruções) |

**Cenário real:**
> O engenheiro pede ao agente para implementar um endpoint REST. O agente consegue gerar o controller, mas ao pedir para criar o service que depende de 3 interfaces, ele já não "lembra" da estrutura completa e pode gerar imports incorretos ou métodos com assinaturas incompatíveis.

---

### Perfil MEDIUM — "O Agente Produtivo"

**Capacidade de contexto:** ~28.000 tokens úteis

**O que o agente CONSEGUE fazer:**
- Analisar **5 a 10 arquivos simultaneamente** (~1.500 linhas de contexto)
- Manter a spec técnica inteira em memória durante a implementação
- Executar fluxos SDD completos: ler spec → gerar código → validar contra spec
- Duas ferramentas MCP consultando o modelo ao mesmo tempo (ex: RAG + Serena)

**O que o agente NÃO consegue fazer bem:**
- Analisar um módulo inteiro (20+ arquivos) de uma vez
- Manter contexto de conversas muito longas (>30 mensagens)
- Executar 4+ ferramentas MCP em paralelo sem fila de espera

**Experiência do engenheiro:**

| Métrica | Valor |
| :--- | :--- |
| Latência por resposta | 2–5 segundos |
| Cold start | 0 segundos (modelo permanente) |
| Qualidade em tarefas curtas | Excelente |
| Qualidade em tarefas longas | Boa (mantém coerência) |

**Cenário real:**
> O engenheiro pede ao agente para refatorar um service que implementa 3 interfaces. O agente consegue ler as interfaces via Serena MCP, manter a spec em contexto, e gerar a implementação completa com os imports corretos. Ao pedir testes, ele ainda "lembra" da implementação e gera mocks adequados.

---

### Perfil POWER — "O Agente Autônomo Completo"

**Capacidade de contexto:** ~58.000 tokens úteis

**O que o agente CONSEGUE fazer:**
- Analisar **um módulo inteiro** (20–40 arquivos, ~5.000 linhas)
- Manter spec + código + testes + review em uma única sessão
- Executar o fluxo SDD completo sem perder contexto em nenhuma etapa
- 4 ferramentas MCP simultâneas (RAG + Serena + Jira + Code Review)
- Raciocínio multi-step longo (chain-of-thought com 10+ passos)

**O que o agente NÃO consegue fazer:**
- Analisar o projeto inteiro (centenas de arquivos) — isso é papel do RAG/vector-search
- Substituir o julgamento humano em decisões arquiteturais de alto nível

**Experiência do engenheiro:**

| Métrica | Valor |
| :--- | :--- |
| Latência por resposta | 1–3 segundos |
| Cold start | 0 segundos (modelo permanente) |
| Qualidade em tarefas curtas | Máxima |
| Qualidade em tarefas longas | Máxima (coerência total) |

**Cenário real:**
> O engenheiro pede ao agente para implementar uma feature completa (spec → code → test → review). O agente lê a spec do Jira via MCP, consulta o RAG para entender padrões existentes, gera a implementação respeitando as interfaces (Serena), cria testes, e faz self-review contra a spec — tudo em uma única sessão sem perder o fio da meada.

---

## Tabela Comparativa Consolidada

| Dimensão | LIGHT | MEDIUM | POWER |
| :--- | :--- | :--- | :--- |
| Arquivos em contexto simultâneo | 1–2 | 5–10 | 20–40 |
| Tokens de contexto útil | ~6K | ~28K | ~58K |
| Ferramentas MCP simultâneas | 1 | 2 | 4 |
| Fluxo SDD completo (sem perda) | Parcial | Sim | Sim + Review |
| Latência média por resposta | 3–8s | 2–5s | 1–3s |
| Cold start | 5–10s | 0s | 0s |
| Perda de qualidade (KV) | Perceptível em textos longos | Imperceptível | Imperceptível |
| Custo de VRAM estimado | ~2–3 GB | ~6–8 GB | ~12–16 GB |

---

## A Regra de Ouro

> **O contexto é o recurso mais precioso do agente.** Um modelo menor com 64K de contexto frequentemente supera um modelo maior com 8K de contexto em tarefas de engenharia, porque o agente consegue "ver" mais código simultaneamente.

A prioridade de investimento de VRAM deve ser:

1. **Primeiro:** Maximizar context length (mais tokens = mais arquivos visíveis)
2. **Segundo:** Usar KV Cache q8_0 (libera VRAM para mais contexto)
3. **Terceiro:** Flash Attention (acelera o processamento do contexto grande)
4. **Por último:** Modelo maior (só se sobrar VRAM após os 3 acima)

---

## Como Configurar no Windows

### Via Variáveis de Ambiente (Permanente)

1. Fechar o Ollama no System Tray (clique direito → Quit)
2. Abrir: **Settings → "Edit environment variables for your account"**
3. Adicionar as variáveis do perfil desejado
4. OK → Apply
5. Reiniciar o Ollama

### Via Script Automatizado (Recomendado)

```powershell
# Detecção automática de hardware
.\scripts\setup.ps1

# Forçar perfil específico
.\scripts\setup.ps1 -Profile power

# Pular configuração de tweaks (manter atual)
.\scripts\setup.ps1 -SkipOllamaTweaks
```

### Verificar Configurações Ativas

```powershell
# Ver variáveis de ambiente do Ollama
Get-ChildItem Env: | Where-Object { $_.Name -like "OLLAMA_*" }

# Ver modelo carregado e uso de memória
ollama ps

# Ver configuração completa de um modelo
ollama show qwen2.5-coder:7b --modelfile
```

---

## Troubleshooting

| Sintoma | Causa Provável | Solução |
| :--- | :--- | :--- |
| Resposta muito lenta (>15s) | Modelo fazendo offload para CPU | Reduzir `num_ctx` ou usar modelo menor |
| "Out of memory" | VRAM insuficiente para modelo + KV | Mudar para perfil LIGHT ou usar `q4_0` |
| Respostas incoerentes no meio | KV Cache q4_0 com contexto longo | Mudar para `q8_0` |
| Modelo descarregado frequentemente | `KEEP_ALIVE` muito curto | Definir `OLLAMA_KEEP_ALIVE=-1` |
| Fila de requisições MCP | `NUM_PARALLEL=1` com múltiplas tools | Aumentar `OLLAMA_NUM_PARALLEL` |
| Flash Attention não ativa | Variável definida mas Ollama não reiniciado | Fechar e reabrir o Ollama |

---

## Referências

- [Ollama Documentation — Context Length](https://docs.ollama.com/context-length)
- [Ollama Documentation — Modelfile Reference](https://docs.ollama.com/modelfile)
- [Bringing K/V Context Quantisation to Ollama](https://smcleod.net/2024/12/bringing-k/v-context-quantisation-to-ollama/) — Sam McLeod
- [Optimizing Ollama Performance on Windows](https://medium.com/@kapildevkhatik2/optimizing-ollama-performance-on-windows-hardware-quantization-parallelism-more-fac04802288e)
