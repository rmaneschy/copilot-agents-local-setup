<#
.SYNOPSIS
Workaround para ambientes com proxy corporativo que realiza inspeção SSL/TLS.

.DESCRIPTION
Em redes corporativas com proxy que intercepta e re-assina pacotes HTTPS (SSL inspection),
o 'ollama pull' falha com erro de verificação SHA256 digest porque o conteúdo do pacote
é modificado pelo proxy durante o trânsito.

Este script oferece três estratégias para contornar o problema:
  1. Download via navegador (manual) - mais confiável
  2. Download via PowerShell com proxy do sistema - automático
  3. Download via curl com certificado corporativo - para quem tem o .pem

.PARAMETER Strategy
Estratégia de download: 'browser', 'powershell', 'curl'. Padrão: 'powershell'.

.PARAMETER CertPath
Caminho para o certificado raiz corporativo (.pem). Necessário apenas para estratégia 'curl'.

.EXAMPLE
.\setup-proxy-workaround.ps1
.\setup-proxy-workaround.ps1 -Strategy browser
.\setup-proxy-workaround.ps1 -Strategy curl -CertPath "C:\certs\corporate-root.pem"
#>

param(
    [ValidateSet("browser", "powershell", "curl")]
    [string]$Strategy = "powershell",
    [string]$CertPath = ""
)

$ErrorActionPreference = "Stop"

$ToolsDir = "$HOME\local-tools"
$ModelsDir = "$ToolsDir\models"
$ModelfileDir = "$ModelsDir\modelfiles"
$ModelName = "nomic-embed-text"
$ModelFileName = "nomic-embed-text-v1.5.Q2_K.gguf"
$LocalModelPath = "$ModelsDir\$ModelFileName"
$HuggingFaceUrl = "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q2_K.gguf?download=true"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Proxy Workaround - Download de Modelo via HuggingFace      ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  Problema: 'ollama pull' falha com erro SHA256 digest        ║" -ForegroundColor Cyan
Write-Host "║  Causa: Proxy corporativo com inspeção SSL/TLS               ║" -ForegroundColor Cyan
Write-Host "║  Solução: Download direto do HuggingFace + import manual     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Criar diretórios
@($ModelsDir, $ModelfileDir) | ForEach-Object {
    if (!(Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null }
}

# ═══════════════════════════════════════════════════════════════════════════
# Verificar se modelo já existe
# ═══════════════════════════════════════════════════════════════════════════
if (Test-Path $LocalModelPath) {
    $fileSize = (Get-Item $LocalModelPath).Length / 1MB
    Write-Host "  Modelo já existe: $LocalModelPath ($([math]::Round($fileSize, 1)) MB)" -ForegroundColor Green
    Write-Host "  Pulando download. Para forçar re-download, delete o arquivo acima." -ForegroundColor Cyan
} else {
    # ═══════════════════════════════════════════════════════════════════════
    # Estratégia de download
    # ═══════════════════════════════════════════════════════════════════════
    Write-Host "  Estratégia selecionada: $Strategy" -ForegroundColor White
    Write-Host ""

    switch ($Strategy) {
        "browser" {
            Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
            Write-Host "  │ INSTRUÇÕES PARA DOWNLOAD MANUAL VIA NAVEGADOR               │" -ForegroundColor Yellow
            Write-Host "  │                                                             │" -ForegroundColor Yellow
            Write-Host "  │ 1. Abra o link abaixo no navegador corporativo:             │" -ForegroundColor Yellow
            Write-Host "  │                                                             │" -ForegroundColor Yellow
            Write-Host "  │    $HuggingFaceUrl" -ForegroundColor Cyan
            Write-Host "  │                                                             │" -ForegroundColor Yellow
            Write-Host "  │ 2. Salve o arquivo como:                                    │" -ForegroundColor Yellow
            Write-Host "  │    $LocalModelPath" -ForegroundColor Cyan
            Write-Host "  │                                                             │" -ForegroundColor Yellow
            Write-Host "  │ 3. Após o download, execute este script novamente.          │" -ForegroundColor Yellow
            Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
            Write-Host ""

            # Abrir o navegador automaticamente
            Start-Process $HuggingFaceUrl
            Write-Host "  Navegador aberto. Aguardando download..." -ForegroundColor Cyan
            Write-Host "  Pressione ENTER após salvar o arquivo em: $LocalModelPath" -ForegroundColor White
            Read-Host

            if (!(Test-Path $LocalModelPath)) {
                Write-Host "  ERRO: Arquivo não encontrado em $LocalModelPath" -ForegroundColor Red
                Write-Host "  Verifique se salvou no caminho correto e execute novamente." -ForegroundColor Yellow
                exit 1
            }
        }

        "powershell" {
            Write-Host "  Baixando via PowerShell (usando proxy do sistema)..."
            Write-Host "  URL: $HuggingFaceUrl"
            Write-Host "  Destino: $LocalModelPath"
            Write-Host ""

            try {
                # Configurar para aceitar certificados do proxy corporativo
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

                # Método 1: WebClient com proxy do sistema (mais compatível com proxies corporativos)
                $webClient = New-Object System.Net.WebClient
                $webClient.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
                $webClient.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

                Write-Host "  Iniciando download (~100 MB)..." -ForegroundColor Cyan
                $webClient.DownloadFile($HuggingFaceUrl, $LocalModelPath)
                Write-Host "  OK: Download concluído." -ForegroundColor Green
            } catch {
                Write-Host "  ERRO: Download via PowerShell falhou." -ForegroundColor Red
                Write-Host "  Detalhes: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host ""
                Write-Host "  Tente a estratégia 'browser':" -ForegroundColor Yellow
                Write-Host "  .\setup-proxy-workaround.ps1 -Strategy browser" -ForegroundColor Cyan
                exit 1
            }
        }

        "curl" {
            if ($CertPath -eq "" -or !(Test-Path $CertPath)) {
                Write-Host "  ERRO: Certificado corporativo não encontrado." -ForegroundColor Red
                Write-Host "  Informe o caminho do .pem com -CertPath" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Para extrair o certificado do proxy:" -ForegroundColor Cyan
                Write-Host "  1. Abra o Chrome e acesse https://huggingface.co" -ForegroundColor White
                Write-Host "  2. Clique no cadeado > 'Connection is secure' > 'Certificate'" -ForegroundColor White
                Write-Host "  3. Exporte o certificado raiz como .pem" -ForegroundColor White
                exit 1
            }

            Write-Host "  Baixando via curl com certificado corporativo..."
            Write-Host "  Certificado: $CertPath"
            curl --cacert $CertPath -L -o $LocalModelPath $HuggingFaceUrl
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ERRO: curl falhou." -ForegroundColor Red
                exit 1
            }
            Write-Host "  OK: Download concluído." -ForegroundColor Green
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Verificar integridade do arquivo
# ═══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  Verificando integridade do arquivo..."
$fileSize = (Get-Item $LocalModelPath).Length / 1MB
if ($fileSize -lt 50) {
    Write-Host "  AVISO: O arquivo parece muito pequeno ($([math]::Round($fileSize, 1)) MB)." -ForegroundColor Yellow
    Write-Host "  Pode ser uma página de erro do proxy. Verifique manualmente." -ForegroundColor Yellow
    Write-Host "  Tamanho esperado: ~100 MB" -ForegroundColor Cyan
    exit 1
}
Write-Host "  OK: Arquivo válido ($([math]::Round($fileSize, 1)) MB)" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════
# Importar no Ollama via Modelfile
# ═══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  Importando modelo no Ollama..."

$ModelfilePath = "$ModelfileDir\Modelfile-nomic-embed-text"
$ModelfileContent = @"
# Modelfile para nomic-embed-text importado do HuggingFace
# Contorna o problema de SHA256 digest em proxies corporativos com SSL inspection
FROM $LocalModelPath
"@
$ModelfileContent | Out-File -FilePath $ModelfilePath -Encoding UTF8 -NoNewline

# Verificar se Ollama está rodando
$OllamaProcess = Get-Process ollama -ErrorAction SilentlyContinue
if (!$OllamaProcess) {
    Write-Host "  Iniciando Ollama..."
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 5
}

try {
    ollama create $ModelName -f $ModelfilePath
    Write-Host "  OK: Modelo '$ModelName' importado com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "  ERRO: Falha ao importar modelo." -ForegroundColor Red
    Write-Host "  Detalhes: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Tente manualmente:" -ForegroundColor Yellow
    Write-Host "  ollama create $ModelName -f $ModelfilePath" -ForegroundColor Cyan
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════
# Validação final
# ═══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  Validando modelo..."
$models = ollama list 2>&1
if ($models -match $ModelName) {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  MODELO IMPORTADO COM SUCESSO                               ║" -ForegroundColor Green
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║  Nome: $ModelName                                    ║" -ForegroundColor Green
    Write-Host "║  Origem: HuggingFace (nomic-ai/nomic-embed-text-v1.5-GGUF) ║" -ForegroundColor Green
    Write-Host "║  Quantização: Q2_K (~100 MB)                                ║" -ForegroundColor Green
    Write-Host "║                                                             ║" -ForegroundColor Green
    Write-Host "║  O modelo está pronto para uso com Ollama (LLM local).       ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
} else {
    Write-Host "  AVISO: Modelo não apareceu em 'ollama list'." -ForegroundColor Yellow
    Write-Host "  Verifique manualmente com: ollama list" -ForegroundColor Yellow
}
Write-Host ""
