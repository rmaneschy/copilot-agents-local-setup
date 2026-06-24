<#
.SYNOPSIS
    Instala e configura o Serena MCP para integração com GitHub Copilot no IntelliJ.

.DESCRIPTION
    Este script automatiza a instalação do Serena MCP, que fornece ferramentas
    semânticas de navegação de código (via LSP) ao GitHub Copilot Agent Mode.
    O Serena complementa o RAG vetorial com capacidades determinísticas de
    find-symbol, find-references, rename e refactoring.

    Pré-requisitos:
    - Windows 11 (sem necessidade de admin)
    - Acesso à internet para download do uv e do Serena

    Workarounds aplicados automaticamente:
    - Windows Long Paths: redireciona TEMP para caminho curto no perfil do usuário
    - Trampoline PE Resources: configura UV_LINK_MODE=copy para evitar hardlinks
    - Antivírus/AppLocker: fallback para pipx quando uv falha por políticas de segurança

.PARAMETER WorkspacePath
    Caminho do workspace principal. Padrão: $env:USERPROFILE\workspace

.PARAMETER ForceReinstall
    Força reinstalação completa do Serena (remove e instala novamente).

.PARAMETER UsePipx
    Força o uso do pipx em vez do uv (útil quando o uv está bloqueado pelo antivírus).

.NOTES
    Autor: Rodrigo Maneschy
    Versão: 2.0.0
#>

param(
    [string]$WorkspacePath = "$env:USERPROFILE\workspace",
    [switch]$ForceReinstall,
    [switch]$UsePipx
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Serena MCP - Setup para GitHub Copilot    ║" -ForegroundColor Cyan
Write-Host "  ║   Navegação Semântica de Código (LSP)       ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Funções auxiliares
# ═══════════════════════════════════════════════════════════════════════════════

function Set-SafeTempDir {
    <#
    .SYNOPSIS
        Redireciona TEMP/TMP para caminho curto dentro do perfil do usuário.
        Resolve o erro "Failed to update Windows PE resources" causado por
        caminhos longos no AppData\Local\Temp que excedem MAX_PATH (260 chars).
    #>
    $script:originalTemp = $env:TEMP
    $script:originalTmp = $env:TMP
    $script:originalTmpDir = $env:TMPDIR

    $shortTmpDir = Join-Path $env:USERPROFILE "tmp"
    if (-not (Test-Path $shortTmpDir)) {
        New-Item -ItemType Directory -Path $shortTmpDir -Force | Out-Null
    }

    $env:TEMP = $shortTmpDir
    $env:TMP = $shortTmpDir
    $env:TMPDIR = $shortTmpDir

    Write-Host "    Workaround: TEMP redirecionado para $shortTmpDir" -ForegroundColor DarkGray
}

function Restore-TempDir {
    <#
    .SYNOPSIS
        Restaura as variáveis TEMP/TMP para os valores originais do sistema.
    #>
    $env:TEMP = $script:originalTemp
    $env:TMP = $script:originalTmp
    $env:TMPDIR = $script:originalTmpDir
    Write-Host "    Workaround: TEMP restaurado para valor original." -ForegroundColor DarkGray
}

function Set-UvCorporateWorkarounds {
    <#
    .SYNOPSIS
        Aplica variáveis de ambiente que resolvem problemas do uv em ambientes
        corporativos com políticas de segurança restritivas.

    .DESCRIPTION
        O uv usa hardlinks por padrão no Windows para instalar executáveis.
        Em ambientes corporativos, isso pode falhar com "Access denied" porque:
        1. O antivírus bloqueia criação de .exe via hardlink em diretórios temp
        2. AppLocker impede execução de binários fora de diretórios aprovados
        3. O trampoline (stub .exe) não consegue ser escrito via PE resource update

        A solução é forçar UV_LINK_MODE=copy (copia em vez de hardlink) e
        definir UV_TOOL_DIR para um caminho curto e previsível.
    #>

    # Forçar cópia em vez de hardlink (evita "Failed to update Windows PE resources")
    $env:UV_LINK_MODE = "copy"
    Write-Host "    Workaround: UV_LINK_MODE=copy (evita hardlink/trampoline)" -ForegroundColor DarkGray

    # Definir diretório de tools em caminho curto e previsível
    $uvToolDir = Join-Path $env:USERPROFILE ".uv\tools"
    if (-not (Test-Path $uvToolDir)) {
        New-Item -ItemType Directory -Path $uvToolDir -Force | Out-Null
    }
    $env:UV_TOOL_DIR = $uvToolDir
    Write-Host "    Workaround: UV_TOOL_DIR=$uvToolDir" -ForegroundColor DarkGray

    # Definir diretório de cache em caminho curto
    $uvCacheDir = Join-Path $env:USERPROFILE ".uv\cache"
    if (-not (Test-Path $uvCacheDir)) {
        New-Item -ItemType Directory -Path $uvCacheDir -Force | Out-Null
    }
    $env:UV_CACHE_DIR = $uvCacheDir
    Write-Host "    Workaround: UV_CACHE_DIR=$uvCacheDir" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 1: Aplicar workarounds para ambiente corporativo
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "  [1/5] Preparando ambiente (workarounds corporativos)..." -ForegroundColor White

Set-SafeTempDir
Set-UvCorporateWorkarounds
Write-Host "    OK: Ambiente preparado para instalação segura." -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 2: Verificar/Instalar gerenciador de pacotes (uv ou pipx)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [2/5] Verificando gerenciador de pacotes..." -ForegroundColor White

$useUv = $true
$installMethod = "uv"

if ($UsePipx) {
    $useUv = $false
    $installMethod = "pipx"
    Write-Host "    Modo forçado: usando pipx (flag -UsePipx)." -ForegroundColor Yellow
}

if ($useUv) {
    $uvPath = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uvPath) {
        Write-Host "    uv não encontrado. Instalando..." -ForegroundColor Gray

        try {
            # Instalar uv via PowerShell installer oficial
            powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

            # Atualizar PATH para a sessão atual
            $uvBinPaths = @(
                "$env:USERPROFILE\.local\bin",
                "$env:USERPROFILE\.cargo\bin",
                "$env:APPDATA\uv"
            )
            foreach ($p in $uvBinPaths) {
                if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
                    $env:PATH = "$p;$env:PATH"
                }
            }

            $uvPath = Get-Command uv -ErrorAction SilentlyContinue
            if ($uvPath) {
                Write-Host "    OK: uv instalado em $($uvPath.Source)" -ForegroundColor Green
            } else {
                throw "uv não encontrado no PATH após instalação"
            }
        }
        catch {
            Write-Host "    AVISO: Falha ao instalar uv. Tentando pipx como fallback..." -ForegroundColor Yellow
            $useUv = $false
            $installMethod = "pipx"
        }
    }
    else {
        Write-Host "    OK: uv encontrado em $($uvPath.Source)" -ForegroundColor Green
    }
}

# Verificar/instalar pipx se necessário
if (-not $useUv) {
    $pipxPath = Get-Command pipx -ErrorAction SilentlyContinue
    if (-not $pipxPath) {
        Write-Host "    pipx não encontrado. Instalando via pip..." -ForegroundColor Gray
        try {
            $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
            if (-not $pythonCmd) {
                $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
            }
            if (-not $pythonCmd) {
                Write-Host "    ERRO: Python não encontrado. Instale Python 3.11+ primeiro." -ForegroundColor Red
                Restore-TempDir
                exit 1
            }
            & $pythonCmd.Source -m pip install --user pipx 2>&1 | Out-Null
            & $pythonCmd.Source -m pipx ensurepath 2>&1 | Out-Null
            $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
            Write-Host "    OK: pipx instalado." -ForegroundColor Green
        }
        catch {
            Write-Host "    ERRO: Falha ao instalar pipx." -ForegroundColor Red
            Restore-TempDir
            exit 1
        }
    }
    else {
        Write-Host "    OK: pipx encontrado em $($pipxPath.Source)" -ForegroundColor Green
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 3: Instalar Serena
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [3/5] Instalando Serena MCP (via $installMethod)..." -ForegroundColor White

$serenaInstalled = $false

if ($ForceReinstall) {
    Write-Host "    Removendo instalação anterior (flag -ForceReinstall)..." -ForegroundColor Gray
    if ($useUv) {
        uv tool uninstall serena-agent 2>&1 | Out-Null
    } else {
        pipx uninstall serena-agent 2>&1 | Out-Null
    }
}

if ($useUv) {
    # ─────────────────────────────────────────────────────────────────────────
    # Tentativa 1: uv tool install com workarounds
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host "    Tentativa 1: uv tool install com UV_LINK_MODE=copy..." -ForegroundColor DarkGray

    try {
        $output = & uv tool install -p 3.13 serena-agent 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    OK: Serena instalado com sucesso via uv!" -ForegroundColor Green
            $serenaInstalled = $true
        } else {
            throw "Exit code: $LASTEXITCODE - $output"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message

        # Verificar se é o erro específico de trampoline/PE resources
        if ($errorMsg -match "trampoline|PE resources|Access.+denied|Acesso.+negado") {
            Write-Host "    AVISO: Erro de trampoline/PE resources detectado." -ForegroundColor Yellow
            Write-Host "    Causa: Política de segurança corporativa bloqueia criação de .exe" -ForegroundColor Yellow
            Write-Host ""

            # ─────────────────────────────────────────────────────────────────
            # Tentativa 2: uv com --python-preference managed-only
            # ─────────────────────────────────────────────────────────────────
            Write-Host "    Tentativa 2: uv com Python do sistema (sem trampoline)..." -ForegroundColor DarkGray

            try {
                $output2 = & uv tool install -p 3.13 serena-agent --python-preference system 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    OK: Serena instalado via uv (Python do sistema)!" -ForegroundColor Green
                    $serenaInstalled = $true
                } else {
                    throw "Exit code: $LASTEXITCODE - $output2"
                }
            }
            catch {
                Write-Host "    Tentativa 2 falhou. Usando pipx como fallback..." -ForegroundColor Yellow
                $useUv = $false
                $installMethod = "pipx"
            }
        }
        else {
            # Pode ser erro de upgrade (já instalado)
            Write-Host "    Tentando upgrade de instalação existente..." -ForegroundColor Gray
            try {
                $upgradeOutput = & uv tool upgrade serena-agent 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    OK: Serena atualizado com sucesso!" -ForegroundColor Green
                    $serenaInstalled = $true
                } else {
                    throw "Upgrade falhou"
                }
            }
            catch {
                Write-Host "    AVISO: uv falhou. Usando pipx como fallback..." -ForegroundColor Yellow
                $useUv = $false
                $installMethod = "pipx"
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Fallback: pipx (não usa trampolines, instala .exe diretamente)
# ─────────────────────────────────────────────────────────────────────────────
if (-not $serenaInstalled) {
    Write-Host ""
    Write-Host "    Fallback: Instalando via pipx (sem trampolines)..." -ForegroundColor Yellow
    Write-Host "    O pipx copia executáveis diretamente, evitando o problema de PE resources." -ForegroundColor DarkGray

    # Verificar pipx
    $pipxPath = Get-Command pipx -ErrorAction SilentlyContinue
    if (-not $pipxPath) {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if (-not $pythonCmd) { $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue }
        if ($pythonCmd) {
            & $pythonCmd.Source -m pip install --user pipx 2>&1 | Out-Null
            & $pythonCmd.Source -m pipx ensurepath 2>&1 | Out-Null
            $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
        }
    }

    try {
        $pipxOutput = & pipx install serena-agent --python python3.13 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    OK: Serena instalado com sucesso via pipx!" -ForegroundColor Green
            $serenaInstalled = $true
        } else {
            # Tentar sem especificar versão do Python
            $pipxOutput2 = & pipx install serena-agent 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    OK: Serena instalado via pipx (Python padrão)!" -ForegroundColor Green
                $serenaInstalled = $true
            } else {
                throw "pipx install falhou: $pipxOutput2"
            }
        }
    }
    catch {
        Write-Host ""
        Write-Host "    ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "    ║  ERRO: Todas as tentativas de instalação falharam.          ║" -ForegroundColor Red
        Write-Host "    ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
        Write-Host "    O ambiente corporativo está bloqueando a criação de executáveis." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    Soluções manuais:" -ForegroundColor White
        Write-Host "      1. Solicitar ao TI a liberação do diretório:" -ForegroundColor Gray
        Write-Host "         $env:USERPROFILE\.local\bin" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "      2. Habilitar Long Paths (requer admin pontual):" -ForegroundColor Gray
        Write-Host "         reg add HKLM\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "      3. Adicionar exclusão no antivírus para:" -ForegroundColor Gray
        Write-Host "         $env:USERPROFILE\.local\bin\*.exe" -ForegroundColor DarkGray
        Write-Host "         $env:USERPROFILE\.uv\tools\**\*.exe" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "      4. Tentar com flag -UsePipx se uv falhou:" -ForegroundColor Gray
        Write-Host "         .\scripts\setup-serena.ps1 -UsePipx" -ForegroundColor DarkGray
        Write-Host ""
        Restore-TempDir
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 4: Inicializar Serena (language servers)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [4/5] Inicializando Serena (backend: language servers)..." -ForegroundColor White

# Atualizar PATH para encontrar o serena recém-instalado
$possiblePaths = @(
    "$env:USERPROFILE\.local\bin",
    "$env:USERPROFILE\.uv\tools\serena-agent\Scripts",
    "$env:APPDATA\Python\Scripts"
)
foreach ($p in $possiblePaths) {
    if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
        $env:PATH = "$p;$env:PATH"
    }
}

$serenaCmd = Get-Command serena -ErrorAction SilentlyContinue
if ($serenaCmd) {
    try {
        & serena init
        Write-Host "    OK: Serena inicializado com sucesso!" -ForegroundColor Green
    }
    catch {
        Write-Host "    AVISO: Inicialização pode requerer interação manual." -ForegroundColor Yellow
        Write-Host "    Execute 'serena init' manualmente se necessário." -ForegroundColor Yellow
    }
} else {
    Write-Host "    AVISO: Comando 'serena' não encontrado no PATH atual." -ForegroundColor Yellow
    Write-Host "    Reinicie o terminal e execute: serena init" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# Etapa 5: Configurar MCP no IntelliJ (GitHub Copilot)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  [5/5] Configurando MCP para GitHub Copilot no IntelliJ..." -ForegroundColor White

$mcpConfigDir = "$env:USERPROFILE\.config\github-copilot\intellij"
$mcpConfigFile = Join-Path $mcpConfigDir "mcp.json"

# Definir a configuração do Serena
$serenaConfig = @{
    type    = "stdio"
    command = "serena"
    args    = @("start-mcp-server", "--context=jb-copilot-plugin")
}

if (Test-Path $mcpConfigFile) {
    Write-Host "    Arquivo mcp.json existente encontrado. Adicionando Serena..." -ForegroundColor Gray
    try {
        $existingConfig = Get-Content $mcpConfigFile -Raw | ConvertFrom-Json

        # Verificar se servers existe
        if (-not $existingConfig.servers) {
            $existingConfig | Add-Member -NotePropertyName "servers" -NotePropertyValue @{}
        }

        # Adicionar/atualizar entrada do Serena
        $existingConfig.servers | Add-Member -NotePropertyName "serena" -NotePropertyValue $serenaConfig -Force

        $existingConfig | ConvertTo-Json -Depth 10 | Set-Content $mcpConfigFile -Encoding UTF8
        Write-Host "    OK: Serena adicionado ao mcp.json existente!" -ForegroundColor Green
    }
    catch {
        Write-Host "    AVISO: Não foi possível modificar mcp.json automaticamente." -ForegroundColor Yellow
        Write-Host "    Adicione manualmente a entrada do Serena (veja README)." -ForegroundColor Yellow
    }
}
else {
    # Criar diretório se não existir
    if (-not (Test-Path $mcpConfigDir)) {
        New-Item -ItemType Directory -Path $mcpConfigDir -Force | Out-Null
    }

    # Criar mcp.json com Serena
    $mcpConfig = @{
        servers = @{
            serena = $serenaConfig
        }
    }

    $mcpConfig | ConvertTo-Json -Depth 10 | Set-Content $mcpConfigFile -Encoding UTF8
    Write-Host "    OK: mcp.json criado com Serena!" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
# Restaurar ambiente e verificação final
# ═══════════════════════════════════════════════════════════════════════════════
Restore-TempDir

Write-Host ""
$serenaCmd = Get-Command serena -ErrorAction SilentlyContinue
if ($serenaCmd) {
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║  INSTALAÇÃO CONCLUÍDA COM SUCESSO!                          ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Serena disponível em: $($serenaCmd.Source)" -ForegroundColor Gray
    Write-Host "  Método de instalação: $installMethod" -ForegroundColor Gray
    Write-Host "  Config MCP: $mcpConfigFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Próximos passos:" -ForegroundColor White
    Write-Host "    1. Reinicie o IntelliJ IDEA" -ForegroundColor Gray
    Write-Host "    2. Abra o Copilot Chat em Agent Mode" -ForegroundColor Gray
    Write-Host "    3. Clique em 'Tools' e verifique se Serena aparece" -ForegroundColor Gray
    Write-Host "    4. No chat, digite:" -ForegroundColor Gray
    Write-Host '       "Ative o projeto atual com Serena"' -ForegroundColor White
    Write-Host ""
    Write-Host "  Dica: Desabilite as tools built-in redundantes:" -ForegroundColor DarkYellow
    Write-Host "    - replace_string_in_file" -ForegroundColor Gray
    Write-Host "    - apply_patch" -ForegroundColor Gray
    Write-Host "    - list_dir" -ForegroundColor Gray
    Write-Host "    - file_search" -ForegroundColor Gray
    Write-Host "    - grep_search" -ForegroundColor Gray
}
else {
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║  INSTALAÇÃO CONCLUÍDA (requer reinício do terminal)         ║" -ForegroundColor Yellow
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  O comando 'serena' não foi encontrado no PATH da sessão atual." -ForegroundColor Yellow
    Write-Host "  Isso é normal — feche e reabra o terminal, depois execute:" -ForegroundColor Gray
    Write-Host "    serena init" -ForegroundColor White
    Write-Host ""
    Write-Host "  Se o erro persistir após reiniciar o terminal:" -ForegroundColor Gray
    Write-Host "    1. Verifique se o diretório está no PATH:" -ForegroundColor Gray
    Write-Host "       $env:USERPROFILE\.local\bin" -ForegroundColor DarkGray
    Write-Host "    2. Tente reinstalar com pipx:" -ForegroundColor Gray
    Write-Host "       .\scripts\setup-serena.ps1 -UsePipx -ForceReinstall" -ForegroundColor DarkGray
}
Write-Host ""
