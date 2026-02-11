<#
.SYNOPSIS
    Extrai e instala chave de produto OEM do Windows

.DESCRIPTION
    Script que verifica, exibe e opcionalmente salva a chave de produto
    Windows armazenada na BIOS/UEFI de computadores OEM.

.NOTES
    Versão: 2.1 (Corrigida - Chaves Balanceadas)
    Requer: Windows 8+ e privilégios de administrador
#>

# ============================================================================
# VERIFICAÇÃO DE PRIVILÉGIOS
# ============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin)
{
	Write-Host "⚠️  ATENÇÃO: Execute como Administrador para resultados confiáveis" -ForegroundColor Yellow
	Write-Host "   Clique com botão direito no PowerShell e selecione 'Executar como Administrador'`n" -ForegroundColor Gray
}

# ============================================================================
# BANNER INICIAL
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          EXTRAÇÃO DE CHAVE OEM DO WINDOWS (BIOS/UEFI)         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n🔍 Buscando chave de produto OEM na BIOS/UEFI..." -ForegroundColor Cyan

# ============================================================================
# PROCESSAMENTO PRINCIPAL
# ============================================================================

try
{
	# ========================================================================
	# COLETA DE INFORMAÇÕES DO SISTEMA
	# ========================================================================
	
	Write-Host "   Acessando serviço de licenciamento..." -ForegroundColor Gray
	
	# Obter informações do sistema
	$OS = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
	$Computer = Get-WmiObject Win32_ComputerSystem -ErrorAction Stop
	$BIOS = Get-WmiObject Win32_BIOS -ErrorAction Stop
	
	# Tentar obter a chave OEM
	$OEMKey = (Get-WmiObject -Query "SELECT OA3xOriginalProductKey FROM SoftwareLicensingService" -ErrorAction Stop).OA3xOriginalProductKey
	
	# ========================================================================
	# VALIDAÇÃO E EXIBIÇÃO DA CHAVE
	# ========================================================================
	
	# ✅ INÍCIO DO IF PRINCIPAL (Linha ~45)
	if ($null -ne $OEMKey -and $OEMKey -ne "")
	{
		
		Write-Host "`n✅ CHAVE OEM ENCONTRADA COM SUCESSO!" -ForegroundColor Green
		Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
		Write-Host "`n   $OEMKey" -ForegroundColor White -BackgroundColor DarkGreen
		Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Green
		
		# ====================================================================
		# INFORMAÇÕES ADICIONAIS DO SISTEMA
		# ====================================================================
		
		Write-Host "`n📊 INFORMAÇÕES DO SISTEMA:" -ForegroundColor Cyan
		Write-Host "   ─────────────────────────────────────────────────────────" -ForegroundColor Gray
		Write-Host "   Sistema Operacional : $($OS.Caption)" -ForegroundColor White
		Write-Host "   Versão              : $($OS.Version)" -ForegroundColor White
		Write-Host "   Fabricante          : $($Computer.Manufacturer)" -ForegroundColor White
		Write-Host "   Modelo              : $($Computer.Model)" -ForegroundColor White
		Write-Host "   Número de Série     : $($BIOS.SerialNumber)" -ForegroundColor White
		Write-Host "   ─────────────────────────────────────────────────────────" -ForegroundColor Gray
		
		# ====================================================================
		# OPÇÃO DE SALVAR EM ARQUIVO
		# ====================================================================
		
		Write-Host "`n💾 Deseja salvar a chave em arquivo?" -ForegroundColor Cyan
		$SaveKey = Read-Host "   Digite S para Sim ou N para Não"
		
		# ✅ INÍCIO DO IF SECUNDÁRIO (Salvar arquivo)
		if ($SaveKey -eq "S" -or $SaveKey -eq "s")
		{
			
			try
			{
				# Definir caminho do arquivo
				$FilePath = "C:\ChaveOEM_$($env:COMPUTERNAME)_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"
				
				# Criar conteúdo do arquivo
				$FileContent = @"
╔════════════════════════════════════════════════════════════════╗
║          CHAVE DE PRODUTO OEM DO WINDOWS (BIOS/UEFI)           ║
╚════════════════════════════════════════════════════════════════╝

Data da extração: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))
Computador: $($env:COMPUTERNAME)
Usuário: $($env:USERNAME)

════════════════════════════════════════════════════════════════

CHAVE OEM: $OEMKey

════════════════════════════════════════════════════════════════

INFORMAÇÕES DO SISTEMA:
- Sistema Operacional : $($OS.Caption)
- Versão              : $($OS.Version)
- Fabricante          : $($Computer.Manufacturer)
- Modelo              : $($Computer.Model)
- Número de Série     : $($BIOS.SerialNumber)

════════════════════════════════════════════════════════════════

⚠️  IMPORTANTE: 
- Mantenha esta chave em local seguro
- Esta chave é vinculada ao hardware original
- Não compartilhe publicamente

════════════════════════════════════════════════════════════════
Script: Instala_licenca_desktop.ps1
Versão: 2.1
════════════════════════════════════════════════════════════════
"@
				
				# Salvar arquivo
				$FileContent | Out-File -FilePath $FilePath -Encoding UTF8 -ErrorAction Stop
				
				Write-Host "`n   ✓ Chave salva com sucesso!" -ForegroundColor Green
				Write-Host "   📁 Local: $FilePath" -ForegroundColor White
				
				# Abrir arquivo automaticamente
				$OpenFile = Read-Host "`n   Deseja abrir o arquivo agora? (S/N)"
				if ($OpenFile -eq "S" -or $OpenFile -eq "s")
				{
					Start-Process notepad.exe -ArgumentList $FilePath
				}
				
			}
			catch
			{
				Write-Host "`n   ❌ Erro ao salvar arquivo:" -ForegroundColor Red
				Write-Host "      $($_.Exception.Message)" -ForegroundColor Red
				Write-Host "`n   💡 Verifique se tem permissão de escrita em C:\" -ForegroundColor Yellow
			}
			
		} # ✅ FIM DO IF SECUNDÁRIO (Salvar arquivo)
		else
		{
			Write-Host "`n   ℹ️  Arquivo não salvo." -ForegroundColor Gray
		}
		
	} # ✅ FIM DO IF PRINCIPAL (Chave encontrada)
	else
	{
		# ====================================================================
		# CHAVE NÃO ENCONTRADA
		# ====================================================================
		
		Write-Host "`n❌ NENHUMA CHAVE OEM ENCONTRADA NA BIOS" -ForegroundColor Red
		Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
		
		Write-Host "`n📋 POSSÍVEIS RAZÕES:" -ForegroundColor Yellow
		Write-Host "   1. Computador montado (não é OEM de fabricante)" -ForegroundColor Gray
		Write-Host "   2. Máquina virtual (não possui BIOS OEM real)" -ForegroundColor Gray
		Write-Host "   3. Windows anterior ao 8 (não suporta OA3.0)" -ForegroundColor Gray
		Write-Host "   4. Licença de varejo ou volume (não gravada na BIOS)" -ForegroundColor Gray
		Write-Host "   5. BIOS/UEFI não possui suporte a OA3.0" -ForegroundColor Gray
		
		Write-Host "`n💡 ALTERNATIVAS:" -ForegroundColor Cyan
		Write-Host "   • Verifique a etiqueta física no equipamento" -ForegroundColor Gray
		Write-Host "   • Consulte a documentação do fabricante" -ForegroundColor Gray
		Write-Host "   • Execute: slmgr /dlv (para ver licença atual)" -ForegroundColor Gray
		Write-Host "   • Execute: wmic path softwarelicensingservice get OA3xOriginalProductKey" -ForegroundColor Gray
	}
	
} # ✅ FIM DO TRY PRINCIPAL
catch
{
	# ========================================================================
	# TRATAMENTO DE ERROS
	# ========================================================================
	
	Write-Host "`n❌ ERRO AO ACESSAR INFORMAÇÕES DE LICENCIAMENTO" -ForegroundColor Red
	Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
	Write-Host "`nDetalhes do erro:" -ForegroundColor Yellow
	Write-Host "   $($_.Exception.Message)" -ForegroundColor Red
	
	Write-Host "`n🔧 SOLUÇÕES SUGERIDAS:" -ForegroundColor Cyan
	Write-Host "   1. Execute como Administrador" -ForegroundColor Gray
	Write-Host "   2. Verifique se o serviço WMI está ativo:" -ForegroundColor Gray
	Write-Host "      Get-Service Winmgmt | Restart-Service" -ForegroundColor DarkGray
	Write-Host "   3. Verifique se o serviço de licenciamento está ativo:" -ForegroundColor Gray
	Write-Host "      Get-Service sppsvc | Start-Service" -ForegroundColor DarkGray
	Write-Host "   4. Tente reiniciar o computador" -ForegroundColor Gray
	
	# Log detalhado para troubleshooting
	Write-Host "`n📝 LOG TÉCNICO (para suporte):" -ForegroundColor DarkGray
	Write-Host "   Tipo de erro: $($_.Exception.GetType().FullName)" -ForegroundColor DarkGray
	Write-Host "   Linha: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
	Write-Host "   Comando: $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
	
} # ✅ FIM DO CATCH PRINCIPAL

# ============================================================================
# FINALIZAÇÃO
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    EXECUÇÃO FINALIZADA                         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`nPressione qualquer tecla para sair..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
