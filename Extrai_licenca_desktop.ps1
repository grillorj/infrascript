<#
.SYNOPSIS
    Extrai e, opcionalmente, salva a chave de produto (Product Key) OEM do Windows.

.DESCRIPTION
    Este script verifica, exibe e permite salvar a chave de produto do Windows (OA3.0)
    que está armazenada diretamente na BIOS/UEFI de computadores de grandes fabricantes (OEM).

.NOTES
    Versão: 2.3 (Final, com correção de codificação e robustez)
    Requer: Windows 8 ou superior e privilégios de Administrador.
#>

# ============================================================================
# VERIFICAÇÃO DE PRIVILÉGIOS DE ADMINISTRADOR
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warning "Acesso negado. Execute este script como Administrador para funcionar corretamente."
    Write-Host "Instrução: Clique com o botão direito no ícone do PowerShell e selecione 'Executar como Administrador'."
    # Pausa para o usuário ler a mensagem antes de fechar automaticamente.
    Start-Sleep -Seconds 10
    exit
}

# ============================================================================
# BANNER INICIAL E MENSAGENS AO USUÁRIO
# ============================================================================
Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          EXTRAÇÃO DE CHAVE OEM DO WINDOWS (BIOS/UEFI)         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "`n🔍 Buscando chave de produto OEM na BIOS/UEFI do sistema..." -ForegroundColor Cyan

# ============================================================================
# BLOCO PRINCIPAL DE EXECUÇÃO COM TRATAMENTO DE ERROS
# ============================================================================
try {
    # ========================================================================
    # COLETA DE INFORMAÇÕES DO SISTEMA USANDO CIM (MODERNO)
    # ========================================================================
    Write-Host "   Acessando serviços de licenciamento e hardware..." -ForegroundColor Gray

    # Obter chave de produto do serviço de licenciamento
    $OEMKey = (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
    
    # ========================================================================
    # SE A CHAVE FOR ENCONTRADA, EXIBIR E OFERECER OPÇÕES
    # ========================================================================
    if (-not [string]::IsNullOrEmpty($OEMKey)) {

        # Coleta informações adicionais apenas se a chave for encontrada
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem
        $Computer = Get-CimInstance -ClassName Win32_ComputerSystem
        $BIOS = Get-CimInstance -ClassName Win32_BIOS

        Write-Host "`n✅ CHAVE OEM ENCONTRADA COM SUCESSO!" -ForegroundColor Green
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "`n   $OEMKey" -ForegroundColor White -BackgroundColor DarkGreen
        Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Green

        # -- Exibição de informações adicionais do sistema --
        Write-Host "`n📊 INFORMAÇÕES DO SISTEMA:" -ForegroundColor Cyan
        Write-Host "   ─────────────────────────────────────────────────────────" -ForegroundColor Gray
        Write-Host "   Sistema Operacional : $($OS.Caption)" -ForegroundColor White
        Write-Host "   Versão              : $($OS.Version)" -ForegroundColor White
        Write-Host "   Fabricante          : $($Computer.Manufacturer)" -ForegroundColor White
        Write-Host "   Modelo              : $($Computer.Model)" -ForegroundColor White
        Write-Host "   Número de Série     : $($BIOS.SerialNumber)" -ForegroundColor White
        Write-Host "   ─────────────────────────────────────────────────────────" -ForegroundColor Gray

        # -- Opção de salvar a chave em um arquivo de texto --
        Write-Host "`n💾 Deseja salvar a chave e as informações em um arquivo de texto?" -ForegroundColor Cyan
        $SaveKey = Read-Host "   Digite 'S' para Sim ou 'N' para Não"

        if ($SaveKey -match '^(s|sim)$') { # Aceita 's', 'S', 'sim', 'Sim', etc.
            try {
                # Salva o arquivo na Área de Trabalho do usuário, que é um local seguro e acessível
                $DesktopPath = [Environment]::GetFolderPath('Desktop')
                $FileName = "ChaveOEM_$($env:COMPUTERNAME)_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"
                $FilePath = Join-Path -Path $DesktopPath -ChildPath $FileName

                # Conteúdo a ser salvo no arquivo
                $FileContent = @"
╔════════════════════════════════════════════════════════════════╗
║          CHAVE DE PRODUTO OEM DO WINDOWS (BIOS/UEFI)           ║
╚════════════════════════════════════════════════════════════════╝

Data da extração: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))
Computador: $($env:COMPUTERNAME)
Usuário: $($env:USERNAME)

════════════════════════════════════════════════════════════════
> CHAVE OEM: $OEMKey
════════════════════════════════════════════════════════════════

INFORMAÇÕES DO SISTEMA:
- Sistema Operacional : $($OS.Caption)
- Versão              : $($OS.Version)
- Fabricante          : $($Computer.Manufacturer)
- Modelo              : $($Computer.Model)
- Número de Série     : $($BIOS.SerialNumber)

════════════════════════════════════════════════════════════════
⚠️  IMPORTANTE:
- Mantenha esta chave em local seguro e privado.
- Esta chave é vinculada ao hardware original deste equipamento.
- Não compartilhe publicamente esta informação.
════════════════════════════════════════════════════════════════
Script: Get-OEMKey.ps1 (v2.3)
"@
                # Salva o arquivo com codificação UTF-8 para garantir compatibilidade
                $FileContent | Out-File -FilePath $FilePath -Encoding UTF8 -ErrorAction Stop

                Write-Host "`n   ✓ Chave salva com sucesso na sua Área de Trabalho!" -ForegroundColor Green
                Write-Host "   📁 Arquivo: $FilePath" -ForegroundColor White

                $OpenFile = Read-Host "`n   Deseja abrir o arquivo agora? (S/N)"
                if ($OpenFile -match '^(s|sim)$') {
                    # Invoke-Item abre o arquivo com o programa padrão do sistema (Bloco de Notas para .txt)
                    Invoke-Item -Path $FilePath
                }
            }
            catch {
                Write-Warning "Ocorreu um erro ao tentar salvar o arquivo."
                Write-Host "   Detalhe do erro: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "   Verifique se você tem permissão para escrever na Área de Trabalho." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`n   ℹ️  Operação cancelada. O arquivo não foi salvo." -ForegroundColor Gray
        }
    }
    else {
        # ====================================================================
        # MENSAGEM CASO NENHUMA CHAVE SEJA ENCONTRADA
        # ====================================================================
        Write-Host "`n❌ NENHUMA CHAVE OEM FOI ENCONTRADA NA BIOS/UEFI DESTE COMPUTADOR." -ForegroundColor Red
        Write-Host "══════════════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "`n📋 POSSÍVEIS RAZÕES:" -ForegroundColor Yellow
        Write-Host "   1. O computador foi montado (não é de um grande fabricante como Dell, HP, etc.)." -ForegroundColor Gray
        Write-Host "   2. Trata-se de uma máquina virtual, que não possui BIOS OEM." -ForegroundColor Gray
        Write-Host "   3. A versão do Windows instalada é anterior ao Windows 8." -ForegroundColor Gray
        Write-Host "   4. A licença utilizada é do tipo Varejo (Retail) ou Volume (VLK), que não é gravada na BIOS." -ForegroundColor Gray
        Write-Host "   5. A BIOS/UEFI do equipamento não possui suporte ao padrão de licenciamento OA3.0." -ForegroundColor Gray
    }
}
catch {
    # ========================================================================
    # TRATAMENTO DE ERROS CRÍTICOS (EX: SERVIÇO WMI PARADO)
    # ========================================================================
    Write-Host "`n❌ ERRO CRÍTICO AO ACESSAR AS INFORMAÇÕES DE LICENCIAMENTO." -ForegroundColor Red
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "`nDetalhes do erro:" -ForegroundColor Yellow
    Write-Host "   $($_.Exception.Message)" -ForegroundColor Red

    Write-Host "`n🔧 SUGESTÕES PARA SOLUÇÃO:" -ForegroundColor Cyan
    Write-Host "   1. Confirme que o script foi executado 'Como Administrador'." -ForegroundColor Gray
    Write-Host "   2. Verifique se os serviços 'Instrumentação de Gerenciamento do Windows' (Winmgmt) e 'Proteção de Software' (sppsvc) estão ativos." -ForegroundColor Gray
    Write-Host "   3. Tente reiniciar o computador e executar o script novamente." -ForegroundColor Gray
}
finally {
    # ============================================================================
    # FINALIZAÇÃO DO SCRIPT (SEMPRE SERÁ EXECUTADO)
    # ============================================================================
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    EXECUÇÃO FINALIZADA                         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    Write-Host "`nPressione qualquer tecla para sair..." -ForegroundColor Gray
    if ($Host.Name -eq "ConsoleHost") {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}