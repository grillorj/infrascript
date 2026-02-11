<#
.SYNOPSIS
    Sistema de Auditoria e Gestão de Usuários Desativados do Active Directory

.DESCRIPTION
    Script empresarial para auditoria completa, análise estatística e gestão
    de usuários desativados no Active Directory da GlobalHitss.

    Funcionalidades:
    - Auditoria detalhada com 35 campos por usuário
    - Exportação em múltiplos formatos (CSV, JSON, Excel-ready, TXT)
    - Análise estatística automática (inatividade, grupos, senhas)
    - Exclusão controlada com confirmação e log detalhado
    - Modo automático para Task Scheduler (parâmetro -Force)
    - Notificação por email HTML com anexos
    - Tratamento robusto de erros e casos extremos

.PARAMETER Operation
    Modo de operação do script:
    - "Audit"  : Apenas auditoria e exportação (padrão, seguro)
    - "Delete" : Auditoria + Exclusão de usuários (requer confirmação)
    - "Both"   : Processo completo com relatório final

.PARAMETER ExportFormat
    Formato(s) de exportação adicional:
    - "CSV"   : Apenas CSV padrão (padrão)
    - "Excel" : CSV + CSV formatado para Excel
    - "JSON"  : CSV + JSON estruturado
    - "All"   : Todos os formatos acima

.PARAMETER Force
    Bypassa confirmações de exclusão para execução automatizada.
    Use com EXTREMO CUIDADO! Destinado apenas para Task Scheduler.
    Todas as execuções com -Force são registradas em log de auditoria.

.EXAMPLE
    .\Manage-DisabledUsers.ps1
    Executa auditoria básica com exportação CSV (modo seguro)

.EXAMPLE
    .\Manage-DisabledUsers.ps1 -Operation Audit -ExportFormat All
    Auditoria completa com todos os formatos de exportação

.EXAMPLE
    .\Manage-DisabledUsers.ps1 -Operation Delete
    Auditoria seguida de exclusão com confirmação manual

.EXAMPLE
    .\Manage-DisabledUsers.ps1 -Operation Delete -Force
    Exclusão AUTOMATIZADA sem confirmação (para Task Scheduler)

.EXAMPLE
    .\Manage-DisabledUsers.ps1 -Operation Both -ExportFormat All -Force
    Processo completo automatizado com todos os formatos

.NOTES
    Autor       : Leonardo Grillo Duarte - GlobalHitss
    Versão      : 3.3 (Produção com Automação)
    Data        : 11/11/2025
    Empresa     : GlobalHitss Brasil
    Contato     : n3-vm-so@globalhitss.com.br

    Changelog v3.3:
    - Adicionado parâmetro -Force para automação
    - Implementado log de auditoria para execuções automatizadas
    - Adicionado validação de contexto de execução
    - Melhorado sistema de segurança para modo -Force
    - Otimizado Get-AuditStatistics com Measure-Object

    Changelog v3.2:
    - Corrigido erro de conversão de tipos datetime para string
    - Corrigido erro "Property 'Count' cannot be found" em MemberOf
    - Implementado tratamento robusto de valores nulos
    - Otimizado processamento de grupos do AD (1 ou múltiplos)
    - Adicionado contador de erros no processamento
    - Melhorado logging e rastreabilidade

    Requisitos:
    - PowerShell 5.1+
    - Módulo ActiveDirectory
    - Permissões de leitura na OU Desativados
    - Permissões de exclusão (apenas para operação Delete)
    - Acesso SMTP para envio de emails

    Segurança:
    - Confirmação obrigatória para exclusões (exceto com -Force)
    - Log detalhado de todas as operações
    - Validação de conectividade AD antes da execução
    - Tratamento de exceções com registro de erros
    - Auditoria especial para execuções com -Force

    Task Scheduler:
    Para configurar execução automatizada, use:
    Programa: powershell.exe
    Argumentos: -ExecutionPolicy Bypass -NoProfile -File "C:\Scripts\Manage-DisabledUsers.ps1" -Operation Delete -Force
#>

[CmdletBinding()]
param (
	[Parameter(Mandatory = $false, HelpMessage = "Modo de operação: Audit, Delete ou Both")]
	[ValidateSet("Audit", "Delete", "Both")]
	[string]$Operation = "Audit",
	[Parameter(Mandatory = $false, HelpMessage = "Formato de exportação: CSV, Excel, JSON ou All")]
	[ValidateSet("CSV", "Excel", "JSON", "All")]
	[string]$ExportFormat = "CSV",
	[Parameter(Mandatory = $false, HelpMessage = "Bypassa confirmações (APENAS para automação)")]
	[switch]$Force
)

#Requires -Modules ActiveDirectory
#Requires -Version 5.1

# ============================================================================
# CONFIGURAÇÃO GLOBAL
# ============================================================================

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Importação do módulo Active Directory
try
{
	Import-Module ActiveDirectory -ErrorAction Stop
	Write-Host "✓ Módulo Active Directory carregado" -ForegroundColor Green
}
catch
{
	Write-Error "Falha ao carregar módulo Active Directory: $_"
	exit 1
}

# ============================================================================
# VARIÁVEIS DE CONFIGURAÇÃO
# ============================================================================

$Config = @{
	# Diretórios
	BaseDirectory			  = "C:\Scripts"
	LogDirectory			  = "C:\Scripts\LOG"
	ExportDirectory		      = "C:\Scripts\EXPORTS"
	ArchiveDirectory		  = "C:\Scripts\ARCHIVE"
	
	# Active Directory
	SearchBase			      = "OU=Desativados,DC=globalhitss,DC=com,DC=br"
	Domain				      = "globalhitss.com.br"
	
	# Email
	SMTPServer			      = "10.230.43.154"
	SMTPPort				  = 25
	EmailFrom				  = "ScriptAD@globalhitss.com.br"
	EmailTo				      = @("relatoriosad@globalhitss.com.br")
	#EmailTo         = @("leonardo.duarte@globalhitss.com.br")  # Testes
	EmailCC				      = @() # Adicione emails para cópia
	
	# Configurações de auditoria
	MaxInactivityDays		  = 30 # Dias para considerar usuário inativo
	Company				      = "GLOBALHITSS"
	
	# Segurança
	AllowForceInBusinessHours = $True # Permite -Force em horário comercial
}

# Timestamp e formatação de datas
$Timestamp = Get-Date
$DateFormat = @{
	FileName  = $Timestamp.ToString("yyyyMMdd_HHmmss")
	Display   = $Timestamp.ToString("dd/MM/yyyy HH:mm:ss")
	FileDate  = $Timestamp.ToString("yyyy-MM-dd")
	ShortDate = $Timestamp.ToString("dd/MM/yyyy")
}

# Definição de caminhos de arquivos
$FilePaths = @{
	AuditCSV	  = Join-Path $Config.ExportDirectory "Auditoria_Desativados_$($DateFormat.FileName).csv"
	AuditExcel    = Join-Path $Config.ExportDirectory "Auditoria_Desativados_$($DateFormat.FileName)_Excel.csv"
	AuditJSON	  = Join-Path $Config.ExportDirectory "Auditoria_Desativados_$($DateFormat.FileName).json"
	SummaryReport = Join-Path $Config.ExportDirectory "Relatorio_Resumo_$($DateFormat.FileName).txt"
	DeletionLog   = Join-Path $Config.LogDirectory "Exclusao_Desativados_$($DateFormat.FileName).log"
	ErrorLog	  = Join-Path $Config.LogDirectory "Erros_$($DateFormat.FileName).log"
	SecurityLog   = Join-Path $Config.LogDirectory "Security_Audit_$($DateFormat.FileName).log"
}

# ============================================================================
# CLASSES DE DADOS
# ============================================================================

class UserAuditData {
	# Identificação
	[int]$Linha
	[string]$Login
	[string]$Nome
	[string]$NomeExibicao
	[string]$Email
	[string]$Dominio
	
	# Dados Organizacionais
	[string]$Descricao
	[string]$Empresa
	[string]$Escritorio
	[string]$Cargo
	[string]$Departamento
	[string]$HistoricoAnterior
	
	# Status da Conta
	[bool]$Habilitado
	[string]$Gerente
	[string]$GerenteEmail
	
	# Datas (string para compatibilidade com CSV)
	[string]$DataCriacao
	[string]$UltimoLogon
	[int]$DiasInativo
	[string]$DataExpiracao
	[int]$ContagemLogon
	
	# Grupos
	[string]$Grupos
	[int]$QuantidadeGrupos
	
	# Segurança
	[bool]$SenhaExpirada
	[bool]$SenhaNuncaExpira
	
	# Dados Pessoais
	[string]$CPF
	[string]$Matricula
	[string]$Telefone
	[string]$Celular
	[string]$Cidade
	[string]$Estado
	[string]$Pais
	
	# Mailbox
	[long]$TamanhoMailbox
	[string]$StatusMailbox
	
	# Metadados
	[string]$DN
	[string]$Observacoes
	[string]$DataAuditoria
	
	UserAuditData()
	{
		$this.DataAuditoria = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
	}
}

class AuditStatistics {
	[int]$TotalUsuarios
	[int]$UsuariosHabilitados
	[int]$UsuariosDesabilitados
	[int]$UsuariosSemLogon
	[int]$UsuariosInativos90Dias
	[int]$UsuariosComSenhaExpirada
	[int]$UsuariosSemGrupos
	[int]$UsuariosComMailbox
	[hashtable]$UsuariosPorDepartamento
	[hashtable]$UsuariosPorEmpresa
	[datetime]$DataExecucao
	
	AuditStatistics()
	{
		$this.UsuariosPorDepartamento = @{ }
		$this.UsuariosPorEmpresa = @{ }
		$this.DataExecucao = Get-Date
	}
}

# ============================================================================
# FUNÇÕES DE VALIDAÇÃO E INICIALIZAÇÃO
# ============================================================================

function Initialize-Environment
{
    <#
    .SYNOPSIS
        Inicializa o ambiente criando diretórios necessários.
    .DESCRIPTION
        Verifica e cria estrutura de diretórios para logs e exportações.
    #>
	
	Write-Host "`n🔧 Inicializando ambiente..." -ForegroundColor Cyan
	
	$Directories = @(
		$Config.LogDirectory,
		$Config.ExportDirectory,
		$Config.ArchiveDirectory
	)
	
	foreach ($Dir in $Directories)
	{
		if (-not (Test-Path -Path $Dir))
		{
			try
			{
				New-Item -Path $Dir -ItemType Directory -Force | Out-Null
				Write-Host "  ✓ Diretório criado: $Dir" -ForegroundColor Green
			}
			catch
			{
				Write-Error "Falha ao criar diretório $Dir : $_"
				exit 1
			}
		}
	}
	
	Write-Host "  ✓ Ambiente inicializado com sucesso`n" -ForegroundColor Green
}

function Test-ADConnection
{
    <#
    .SYNOPSIS
        Valida conectividade com o Active Directory.
    .DESCRIPTION
        Testa conexão com o domínio e identifica o controlador de domínio.
    .OUTPUTS
        Boolean - True se conectado, False caso contrário
    #>
	
	Write-Host "🔍 Validando conexão com Active Directory..." -ForegroundColor Yellow
	
	try
	{
		$Domain = Get-ADDomain -ErrorAction Stop
		Write-Host "  ✓ Conectado ao domínio: $($Domain.DNSRoot)" -ForegroundColor Green
		Write-Host "  ✓ Controlador: $($Domain.PDCEmulator)`n" -ForegroundColor Green
		return $true
	}
	catch
	{
		Write-Error "Falha na conexão com AD: $_"
		return $false
	}
}

function Test-OUExists
{
    <#
    .SYNOPSIS
        Valida se a OU especificada existe.
    .PARAMETER OUPath
        Caminho completo da OU (Distinguished Name)
    .OUTPUTS
        Boolean - True se OU existe, False caso contrário
    #>
	param (
		[Parameter(Mandatory)]
		[string]$OUPath
	)
	
	Write-Host "🔍 Validando Unidade Organizacional..." -ForegroundColor Yellow
	
	try
	{
		$OU = Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction Stop
		Write-Host "  ✓ OU localizada: $($OU.Name)" -ForegroundColor Green
		Write-Host "  ✓ Caminho: $OUPath`n" -ForegroundColor Green
		return $true
	}
	catch
	{
		Write-Error "OU não encontrada: $OUPath"
		return $false
	}
}

function Write-SecurityAuditLog
{
    <#
    .SYNOPSIS
        Registra eventos de segurança em log dedicado.
    .DESCRIPTION
        Cria log de auditoria para operações sensíveis, especialmente
        execuções com parâmetro -Force.
    .PARAMETER Message
        Mensagem a ser registrada
    .PARAMETER Severity
        Nível de severidade: Info, Warning, Critical
    #>
	param (
		[Parameter(Mandatory)]
		[string]$Message,
		[Parameter(Mandatory = $false)]
		[ValidateSet("Info", "Warning", "Critical")]
		[string]$Severity = "Info"
	)
	
	$LogEntry = @"
[$($DateFormat.Display)] [$Severity] $Message
Usuário: $($env:USERNAME)
Máquina: $($env:COMPUTERNAME)
Domínio: $($env:USERDNSDOMAIN)
Processo: $PID
---
"@
	
	$LogEntry | Out-File -FilePath $FilePaths.SecurityLog -Append -Encoding UTF8
}

# ============================================================================
# FUNÇÕES DE COLETA E PROCESSAMENTO DE DADOS
# ============================================================================

function Get-EnhancedUserData
{
    <#
    .SYNOPSIS
        Coleta dados detalhados de um usuário do AD com validações robustas.

    .DESCRIPTION
        Extrai 35 campos de informação de um objeto ADUser, incluindo:
        - Dados básicos (login, nome, email)
        - Dados organizacionais (empresa, cargo, departamento)
        - Status da conta (habilitado, senha expirada)
        - Datas (criação, último logon, expiração)
        - Grupos e permissões
        - Análise de inatividade
        - Observações automáticas

        Versão 3.3 - Tratamento robusto de:
        - Valores nulos em todos os campos
        - MemberOf como string (1 grupo) ou array (múltiplos)
        - Datas ausentes (LastLogonDate, AccountExpirationDate)

    .PARAMETER ADUser
        Objeto ADUser retornado por Get-ADUser com Properties *

    .PARAMETER Index
        Número sequencial do usuário no processamento

    .OUTPUTS
        UserAuditData - Objeto com todos os dados coletados
        $null - Em caso de erro no processamento

    .EXAMPLE
        $user = Get-ADUser "jsilva" -Properties *
        $data = Get-EnhancedUserData -ADUser $user -Index 1
    #>
	
	param (
		[Parameter(Mandatory)]
		[Microsoft.ActiveDirectory.Management.ADUser]$ADUser,
		[Parameter(Mandatory)]
		[int]$Index
	)
	
	try
	{
		# Criação do objeto de dados
		$UserData = [UserAuditData]::new()
		
		# ========================================================================
		# DADOS BÁSICOS
		# ========================================================================
		
		$UserData.Linha = $Index
		$UserData.Login = if ($ADUser.SamAccountName) { $ADUser.SamAccountName }
		else { "N/A" }
		$UserData.Nome = if ($ADUser.CN) { $ADUser.CN }
		else { "N/A" }
		$UserData.NomeExibicao = if ($ADUser.DisplayName) { $ADUser.DisplayName }
		else { "N/A" }
		$UserData.Email = if ($ADUser.EmailAddress) { $ADUser.EmailAddress }
		else { "" }
		$UserData.Dominio = if ($ADUser.UserPrincipalName) { $ADUser.UserPrincipalName }
		else { "N/A" }
		
		# ========================================================================
		# DADOS ORGANIZACIONAIS
		# ========================================================================
		
		$UserData.Descricao = if ($ADUser.Description) { $ADUser.Description }
		else { "" }
		$UserData.Empresa = if ($ADUser.Company) { $ADUser.Company }
		else { "" }
		$UserData.Escritorio = if ($ADUser.Office) { $ADUser.Office }
		else { "" }
		$UserData.Cargo = if ($ADUser.Title) { $ADUser.Title }
		else { "" }
		$UserData.Departamento = if ($ADUser.Department) { $ADUser.Department }
		else { "" }
		$UserData.HistoricoAnterior = if ($ADUser.HomePage) { $ADUser.HomePage }
		else { "" }
		
		# ========================================================================
		# STATUS DA CONTA
		# ========================================================================
		
		$UserData.Habilitado = if ($null -ne $ADUser.Enabled) { $ADUser.Enabled }
		else { $false }
		$UserData.SenhaExpirada = if ($null -ne $ADUser.PasswordExpired) { $ADUser.PasswordExpired }
		else { $false }
		$UserData.SenhaNuncaExpira = if ($null -ne $ADUser.PasswordNeverExpires) { $ADUser.PasswordNeverExpires }
		else { $false }
		
		# ========================================================================
		# GERENTE
		# ========================================================================
		
		if ($ADUser.Manager)
		{
			try
			{
				$Manager = Get-ADUser -Identity $ADUser.Manager -Properties EmailAddress -ErrorAction SilentlyContinue
				if ($Manager)
				{
					$UserData.Gerente = if ($Manager.Name) { $Manager.Name }
					else { $ADUser.Manager }
					$UserData.GerenteEmail = if ($Manager.EmailAddress) { $Manager.EmailAddress }
					else { "N/A" }
				}
				else
				{
					$UserData.Gerente = $ADUser.Manager
					$UserData.GerenteEmail = "N/A"
				}
			}
			catch
			{
				$UserData.Gerente = $ADUser.Manager
				$UserData.GerenteEmail = "N/A"
			}
		}
		else
		{
			$UserData.Gerente = "Sem gerente"
			$UserData.GerenteEmail = "N/A"
		}
		
		# ========================================================================
		# DATAS (TRATAMENTO SEGURO - CONVERSÃO PARA STRING)
		# ========================================================================
		
		# Data de Criação (sempre existe)
		$UserData.DataCriacao = if ($ADUser.Created)
		{
			$ADUser.Created.ToString("dd/MM/yyyy HH:mm:ss")
		}
		else
		{
			"Não disponível"
		}
		
		# Último Logon (pode ser nulo)
		if ($ADUser.LastLogonDate)
		{
			$UserData.UltimoLogon = $ADUser.LastLogonDate.ToString("dd/MM/yyyy HH:mm:ss")
		}
		else
		{
			$UserData.UltimoLogon = "Nunca logou"
		}
		
		# Data de Expiração (pode ser nula)
		if ($ADUser.AccountExpirationDate)
		{
			$UserData.DataExpiracao = $ADUser.AccountExpirationDate.ToString("dd/MM/yyyy")
		}
		else
		{
			$UserData.DataExpiracao = "Sem expiração"
		}
		
		# ========================================================================
		# CÁLCULO DE DIAS DE INATIVIDADE
		# ========================================================================
		
		if ($ADUser.LastLogonDate)
		{
			$UserData.DiasInativo = (New-TimeSpan -Start $ADUser.LastLogonDate -End (Get-Date)).Days
		}
		else
		{
			$UserData.DiasInativo = -1 # Indica que nunca fez logon
		}
		
		# Contagem de logon
		$UserData.ContagemLogon = if ($ADUser.logonCount) { $ADUser.logonCount }
		else { 0 }
		
		# ========================================================================
		# PROCESSAMENTO DE GRUPOS (CORREÇÃO PRINCIPAL v3.2)
		# ========================================================================
		
		if ($ADUser.MemberOf)
		{
			# Força conversão para array - resolve problema de 1 grupo
			# @() garante que sempre será array, mesmo com 1 elemento
			$MemberOfArray = @($ADUser.MemberOf)
			
			# Extrai nomes dos grupos
			$GroupNames = $MemberOfArray | ForEach-Object {
				($_ -split ',')[0] -replace 'CN=', ''
			}
			
			# Concatena grupos com separador
			$UserData.Grupos = $GroupNames -join ' | '
			
			# Contagem segura - array sempre tem propriedade Count
			$UserData.QuantidadeGrupos = $MemberOfArray.Count
		}
		else
		{
			$UserData.Grupos = "Nenhum grupo"
			$UserData.QuantidadeGrupos = 0
		}
		
		# ========================================================================
		# DADOS ADICIONAIS
		# ========================================================================
		
		$UserData.DN = if ($ADUser.DistinguishedName) { $ADUser.DistinguishedName }
		else { "N/A" }
		$UserData.CPF = if ($ADUser.EmployeeNumber) { $ADUser.EmployeeNumber }
		else { "" }
		$UserData.Matricula = if ($ADUser.EmployeeID) { $ADUser.EmployeeID }
		else { "" }
		$UserData.Telefone = if ($ADUser.telephoneNumber) { $ADUser.telephoneNumber }
		else { "" }
		$UserData.Celular = if ($ADUser.mobile) { $ADUser.mobile }
		else { "" }
		$UserData.Cidade = if ($ADUser.City) { $ADUser.City }
		else { "" }
		$UserData.Estado = if ($ADUser.State) { $ADUser.State }
		else { "" }
		$UserData.Pais = if ($ADUser.Country) { $ADUser.Country }
		else { "" }
		
		# ========================================================================
		# ANÁLISE DE MAILBOX
		# ========================================================================
		
		if ($ADUser.EmailAddress)
		{
			$UserData.StatusMailbox = "Email configurado"
		}
		else
		{
			$UserData.StatusMailbox = "Sem email"
		}
		
		# Tamanho do mailbox (placeholder - requer integração com Exchange)
		$UserData.TamanhoMailbox = 0
		
		# ========================================================================
		# OBSERVAÇÕES AUTOMÁTICAS
		# ========================================================================
		
		$Observations = @()
		
		# Verifica inatividade
		if ($UserData.DiasInativo -gt $Config.MaxInactivityDays -and $UserData.DiasInativo -ne -1)
		{
			$Observations += "Inativo há mais de $($Config.MaxInactivityDays) dias ($($UserData.DiasInativo) dias)"
		}
		
		# Nunca logou
		if ($UserData.DiasInativo -eq -1)
		{
			$Observations += "Nunca realizou logon"
		}
		
		# Sem grupos
		if ($UserData.QuantidadeGrupos -eq 0)
		{
			$Observations += "Sem grupos atribuídos"
		}
		
		# Senha expirada
		if ($UserData.SenhaExpirada)
		{
			$Observations += "Senha expirada"
		}
		
		# Conta desabilitada
		if (-not $UserData.Habilitado)
		{
			$Observations += "Conta desabilitada"
		}
		
		# Sem email
		if (-not $UserData.Email)
		{
			$Observations += "Sem email configurado"
		}
		
		# Consolida observações
		$UserData.Observacoes = if ($Observations.Count -gt 0)
		{
			$Observations -join '; '
		}
		else
		{
			"Nenhuma observação"
		}
		
		return $UserData
	}
	catch
	{
		Write-Warning "Erro ao processar usuário $($ADUser.SamAccountName): $_"
		$_ | Out-File -FilePath $FilePaths.ErrorLog -Append -Encoding UTF8
		return $null
	}
}

function Get-DisabledUsersAudit
{
    <#
    .SYNOPSIS
        Realiza auditoria completa dos usuários na OU Desativados.

    .DESCRIPTION
        Busca todos os usuários na OU configurada e processa seus dados
        usando Get-EnhancedUserData. Retorna lista de objetos UserAuditData.

    .OUTPUTS
        System.Collections.Generic.List[UserAuditData] - Lista de usuários auditados
        $null - Se nenhum usuário encontrado ou erro na busca
    #>
	
	Write-Host "`n📊 INICIANDO AUDITORIA DE USUÁRIOS" -ForegroundColor Cyan
	Write-Host "========================================`n" -ForegroundColor Cyan
	
	try
	{
		# Busca de usuários
		Write-Host "🔍 Buscando usuários na OU Desativados..." -ForegroundColor Yellow
		
		$ADUsers = Get-ADUser -Filter * `
							  -SearchBase $Config.SearchBase `
							  -Properties * `
							  -ErrorAction Stop
		
		if ($null -eq $ADUsers -or $ADUsers.Count -eq 0)
		{
			Write-Host "  ⚠️  Nenhum usuário encontrado na OU especificada`n" -ForegroundColor Yellow
			return $null
		}
		
		$TotalUsers = if ($ADUsers -is [Array]) { $ADUsers.Count }
		else { 1 }
		Write-Host "  ✓ Encontrados $TotalUsers usuário(s)`n" -ForegroundColor Green
		
		# Processamento dos usuários
		Write-Host "⚙️  Processando dados dos usuários..." -ForegroundColor Yellow
		
		$AuditData = [System.Collections.Generic.List[UserAuditData]]::new()
		$ProcessedCount = 0
		$ErrorCount = 0
		
		foreach ($ADUser in $ADUsers)
		{
			$ProcessedCount++
			$PercentComplete = [math]::Round(($ProcessedCount / $TotalUsers) * 100, 2)
			
			Write-Progress -Activity "Auditando usuários" `
						   -Status "Processando $ProcessedCount de $TotalUsers ($PercentComplete%)" `
						   -PercentComplete $PercentComplete
			
			$UserData = Get-EnhancedUserData -ADUser $ADUser -Index $ProcessedCount
			
			if ($null -ne $UserData)
			{
				$AuditData.Add($UserData)
			}
			else
			{
				$ErrorCount++
			}
		}
		
		Write-Progress -Activity "Auditando usuários" -Completed
		
		if ($ErrorCount -gt 0)
		{
			Write-Host "  ⚠️  $ErrorCount usuário(s) com erro no processamento" -ForegroundColor Yellow
		}
		
		Write-Host "  ✓ Processamento concluído: $($AuditData.Count) usuários auditados`n" -ForegroundColor Green
		
		return $AuditData
	}
	catch
	{
		Write-Error "Erro durante auditoria: $_"
		$_ | Out-File -FilePath $FilePaths.ErrorLog -Append -Encoding UTF8
		return $null
	}
}

# ============================================================================
# FUNÇÕES DE ANÁLISE E ESTATÍSTICAS (VERSÃO 3.3 OTIMIZADA)
# ============================================================================

function Get-AuditStatistics
{
    <#
    .SYNOPSIS
        Calcula estatísticas detalhadas dos dados auditados.

    .DESCRIPTION
        Versão 3.3 - Usa Measure-Object para contagem 100% confiável.
        Compatível com PowerShell 5.1 e superior.
        Resolve definitivamente o erro "Property 'Count' cannot be found".

    .PARAMETER AuditData
        Lista de objetos UserAuditData para análise

    .OUTPUTS
        AuditStatistics - Objeto com estatísticas calculadas

    .EXAMPLE
        $stats = Get-AuditStatistics -AuditData $auditData
    #>
	param (
		[Parameter(Mandatory)]
		[System.Collections.Generic.List[UserAuditData]]$AuditData
	)
	
	Write-Host "📈 Calculando estatísticas..." -ForegroundColor Yellow
	
	$Stats = [AuditStatistics]::new()
	
	# Total de usuários (sempre confiável)
	$Stats.TotalUsuarios = $AuditData.Count
	
	# ✅ CORREÇÃO v3.3: Usa Measure-Object para contagem 100% robusta
	# Mais confiável que @() + .Count em PowerShell 5.1
	$Stats.UsuariosHabilitados = ($AuditData | Where-Object { $_.Habilitado } | Measure-Object).Count
	$Stats.UsuariosDesabilitados = ($AuditData | Where-Object { -not $_.Habilitado } | Measure-Object).Count
	$Stats.UsuariosSemLogon = ($AuditData | Where-Object { $_.DiasInativo -eq -1 } | Measure-Object).Count
	$Stats.UsuariosInativos90Dias = ($AuditData | Where-Object { $_.DiasInativo -gt 90 -and $_.DiasInativo -ne -1 } | Measure-Object).Count
	$Stats.UsuariosComSenhaExpirada = ($AuditData | Where-Object { $_.SenhaExpirada } | Measure-Object).Count
	$Stats.UsuariosSemGrupos = ($AuditData | Where-Object { $_.QuantidadeGrupos -eq 0 } | Measure-Object).Count
	$Stats.UsuariosComMailbox = ($AuditData | Where-Object { $_.Email -and $_.Email -ne "" } | Measure-Object).Count
	
	# Agrupamento por departamento (com validação robusta)
	$DeptGroups = $AuditData |
	Where-Object { $_.Departamento -and $_.Departamento -ne "" } |
	Group-Object -Property Departamento
	
	if ($DeptGroups)
	{
		foreach ($group in $DeptGroups)
		{
			$Stats.UsuariosPorDepartamento[$group.Name] = $group.Count
		}
	}
	
	# Agrupamento por empresa (com validação robusta)
	$CompanyGroups = $AuditData |
	Where-Object { $_.Empresa -and $_.Empresa -ne "" } |
	Group-Object -Property Empresa
	
	if ($CompanyGroups)
	{
		foreach ($group in $CompanyGroups)
		{
			$Stats.UsuariosPorEmpresa[$group.Name] = $group.Count
		}
	}
	
	Write-Host "  ✓ Estatísticas calculadas`n" -ForegroundColor Green
	
	return $Stats
}

# ============================================================================
# FUNÇÕES DE EXPORTAÇÃO
# ============================================================================

function Export-AuditToCSV
{
    <#
    .SYNOPSIS
        Exporta dados de auditoria para CSV formatado.

    .PARAMETER AuditData
        Lista de objetos UserAuditData para exportação

    .PARAMETER FilePath
        Caminho completo do arquivo CSV de destino

    .OUTPUTS
        Boolean - True se exportação bem-sucedida, False caso contrário
    #>
	param (
		[Parameter(Mandatory)]
		[System.Collections.Generic.List[UserAuditData]]$AuditData,
		[Parameter(Mandatory)]
		[string]$FilePath
	)
	
	Write-Host "💾 Exportando para CSV..." -ForegroundColor Yellow
	
	try
	{
		# Exportação com encoding UTF-8 e delimitador ponto-e-vírgula
		$AuditData | Export-Csv -Path $FilePath `
								-Delimiter ';' `
								-Encoding UTF8 `
								-NoTypeInformation `
								-Force
		
		$FileSize = (Get-Item $FilePath).Length / 1KB
		Write-Host "  ✓ CSV exportado: $FilePath" -ForegroundColor Green
		Write-Host "  ✓ Tamanho: $([math]::Round($FileSize, 2)) KB`n" -ForegroundColor Green
		
		return $true
	}
	catch
	{
		Write-Error "Erro ao exportar CSV: $_"
		return $false
	}
}

function Export-AuditToExcelReady
{
    <#
    .SYNOPSIS
        Exporta dados em formato otimizado para Excel.

    .DESCRIPTION
        Cria CSV com cabeçalho formatado para abertura direta no Excel.
    #>
	param (
		[Parameter(Mandatory)]
		[System.Collections.Generic.List[UserAuditData]]$AuditData,
		[Parameter(Mandatory)]
		[string]$FilePath
	)
	
	Write-Host "📊 Exportando formato Excel-ready..." -ForegroundColor Yellow
	
	try
	{
		# Criação de cabeçalho formatado
		$Header = @"
"RELATÓRIO DE AUDITORIA - USUÁRIOS DESATIVADOS"
"Empresa: $($Config.Company)"
"Data da Auditoria: $($DateFormat.Display)"
"Total de Usuários: $($AuditData.Count)"
""
"DADOS DETALHADOS"
"@
		
		$Header | Out-File -FilePath $FilePath -Encoding UTF8
		
		# Exportação dos dados
		$AuditData | Export-Csv -Path $FilePath `
								-Delimiter ';' `
								-Encoding UTF8 `
								-NoTypeInformation `
								-Append
		
		Write-Host "  ✓ Arquivo Excel-ready exportado`n" -ForegroundColor Green
		return $true
	}
	catch
	{
		Write-Error "Erro ao exportar Excel-ready: $_"
		return $false
	}
}

function Export-AuditToJSON
{
    <#
    .SYNOPSIS
        Exporta dados de auditoria para JSON estruturado.

    .DESCRIPTION
        Cria JSON com metadados, estatísticas e dados de usuários.
    #>
	param (
		[Parameter(Mandatory)]
		[System.Collections.Generic.List[UserAuditData]]$AuditData,
		[Parameter(Mandatory)]
		[string]$FilePath,
		[Parameter(Mandatory)]
		[AuditStatistics]$Statistics
	)
	
	Write-Host "📄 Exportando para JSON..." -ForegroundColor Yellow
	
	try
	{
		$JSONStructure = @{
			Metadata = @{
				Company	     = $Config.Company
				AuditDate    = $DateFormat.Display
				TotalUsers   = $AuditData.Count
				ExportFormat = "JSON"
				Version	     = "3.3"
			}
			Statistics = @{
				TotalUsuarios		     = $Statistics.TotalUsuarios
				UsuariosHabilitados	     = $Statistics.UsuariosHabilitados
				UsuariosDesabilitados    = $Statistics.UsuariosDesabilitados
				UsuariosSemLogon		 = $Statistics.UsuariosSemLogon
				UsuariosInativos90Dias   = $Statistics.UsuariosInativos90Dias
				UsuariosComSenhaExpirada = $Statistics.UsuariosComSenhaExpirada
				UsuariosSemGrupos	     = $Statistics.UsuariosSemGrupos
				UsuariosComMailbox	     = $Statistics.UsuariosComMailbox
				UsuariosPorDepartamento  = $Statistics.UsuariosPorDepartamento
				UsuariosPorEmpresa	     = $Statistics.UsuariosPorEmpresa
			}
			Users    = $AuditData
		}
		
		$JSONStructure | ConvertTo-Json -Depth 10 | Out-File -FilePath $FilePath -Encoding UTF8
		
		Write-Host "  ✓ JSON exportado com sucesso`n" -ForegroundColor Green
		return $true
	}
	catch
	{
		Write-Error "Erro ao exportar JSON: $_"
		return $false
	}
}

function Export-SummaryReport
{
    <#
    .SYNOPSIS
        Gera relatório resumido em texto formatado.
    #>
	param (
		[Parameter(Mandatory)]
		[AuditStatistics]$Statistics,
		[Parameter(Mandatory)]
		[string]$FilePath
	)
	
	Write-Host "📋 Gerando relatório resumido..." -ForegroundColor Yellow
	
	$Report = @"
╔════════════════════════════════════════════════════════════════════════════╗
║                    RELATÓRIO DE AUDITORIA - RESUMO EXECUTIVO               ║
╚════════════════════════════════════════════════════════════════════════════╝

INFORMAÇÕES GERAIS
══════════════════════════════════════════════════════════════════════════════
Empresa:              $($Config.Company)
Data da Auditoria:    $($DateFormat.Display)
OU Auditada:          $($Config.SearchBase)

ESTATÍSTICAS GERAIS
══════════════════════════════════════════════════════════════════════════════
Total de Usuários:                    $($Statistics.TotalUsuarios)
Usuários Habilitados:                 $($Statistics.UsuariosHabilitados)
Usuários Desabilitados:               $($Statistics.UsuariosDesabilitados)

ANÁLISE DE ATIVIDADE
══════════════════════════════════════════════════════════════════════════════
Usuários sem Logon:                   $($Statistics.UsuariosSemLogon)
Inativos há mais de 90 dias:          $($Statistics.UsuariosInativos90Dias)

ANÁLISE DE SEGURANÇA
══════════════════════════════════════════════════════════════════════════════
Usuários com Senha Expirada:          $($Statistics.UsuariosComSenhaExpirada)
Usuários sem Grupos:                  $($Statistics.UsuariosSemGrupos)

RECURSOS
══════════════════════════════════════════════════════════════════════════════
Usuários com Mailbox:                 $($Statistics.UsuariosComMailbox)

DISTRIBUIÇÃO POR DEPARTAMENTO
══════════════════════════════════════════════════════════════════════════════
"@
	
	if ($Statistics.UsuariosPorDepartamento.Count -gt 0)
	{
		$Statistics.UsuariosPorDepartamento.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
			$Report += "`n$($_.Key.PadRight(40)) : $($_.Value)"
		}
	}
	else
	{
		$Report += "`nNenhum departamento identificado"
	}
	
	$Report += @"

`nDISTRIBUIÇÃO POR EMPRESA
══════════════════════════════════════════════════════════════════════════════
"@
	
	if ($Statistics.UsuariosPorEmpresa.Count -gt 0)
	{
		$Statistics.UsuariosPorEmpresa.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
			$Report += "`n$($_.Key.PadRight(40)) : $($_.Value)"
		}
	}
	else
	{
		$Report += "`nNenhuma empresa identificada"
	}
	
	$Report += @"

`n══════════════════════════════════════════════════════════════════════════════
Relatório gerado automaticamente pelo sistema de auditoria do Active Directory
Versão: 3.3 (Produção com Automação)
══════════════════════════════════════════════════════════════════════════════
"@
	
	$Report | Out-File -FilePath $FilePath -Encoding UTF8
	
	Write-Host "  ✓ Relatório resumido gerado`n" -ForegroundColor Green
}

# ============================================================================
# FUNÇÕES DE EXCLUSÃO (COM SUPORTE A -Force)
# ============================================================================

function Remove-AuditedUsers
{
    <#
    .SYNOPSIS
        Remove usuários auditados do Active Directory com confirmação.

    .DESCRIPTION
        Solicita confirmação explícita e remove usuários um por um,
        registrando sucessos e erros em log detalhado.

        NOVIDADE v3.3: Suporta parâmetro -Force para execução automatizada
        sem confirmação manual. Todas as execuções com -Force são registradas
        em log de auditoria de segurança.

    .PARAMETER AuditData
        Lista de usuários a serem excluídos

    .PARAMETER Force
        Bypassa confirmação de segurança (APENAS para automação)
        USO RECOMENDADO: Task Scheduler, scripts automatizados
        CUIDADO: Esta operação é IRREVERSÍVEL!

    .OUTPUTS
        Hashtable com contadores: Success, Errors, Cancelled

    .EXAMPLE
        # Execução manual com confirmação
        Remove-AuditedUsers -AuditData $users

    .EXAMPLE
        # Execução automatizada sem confirmação
        Remove-AuditedUsers -AuditData $users -Force
    #>
	param (
		[Parameter(Mandatory)]
		[System.Collections.Generic.List[UserAuditData]]$AuditData,
		[Parameter(Mandatory = $false)]
		[switch]$Force
	)
	
	Write-Host "`n🗑️  INICIANDO PROCESSO DE EXCLUSÃO" -ForegroundColor Cyan
	Write-Host "========================================`n" -ForegroundColor Cyan
	
	$TotalUsers = $AuditData.Count
	$SuccessCount = 0
	$ErrorCount = 0
	
	# ========================================================================
	# CONFIRMAÇÃO CONDICIONAL (BASEADA EM -Force)
	# ========================================================================
	
	if (-not $Force)
	{
		# ✅ MODO MANUAL: Solicita confirmação explícita
		Write-Host "⚠️  ATENÇÃO: Esta operação irá excluir $TotalUsers usuário(s) permanentemente!" -ForegroundColor Red
		Write-Host "Esta ação NÃO PODE SER DESFEITA!`n" -ForegroundColor Red
		$Confirmation = Read-Host "Digite 'CONFIRMAR' (em maiúsculas) para prosseguir"
		
		if ($Confirmation -ne "CONFIRMAR")
		{
			Write-Host "`n❌ Operação cancelada pelo usuário`n" -ForegroundColor Yellow
			
			# Log de cancelamento
			Write-SecurityAuditLog -Message "Exclusão cancelada pelo usuário" -Severity "Info"
			
			return @{
				Success   = 0
				Errors    = 0
				Cancelled = $true
			}
		}
		
		Write-Host "`n✓ Confirmação recebida. Prosseguindo...`n" -ForegroundColor Green
	}
	else
	{
		# ✅ MODO AUTOMÁTICO: Bypassa confirmação
		Write-Host "🤖 MODO AUTOMÁTICO ATIVADO (-Force)" -ForegroundColor Yellow
		Write-Host "⚠️  Excluindo $TotalUsers usuário(s) SEM confirmação manual..." -ForegroundColor Yellow
		Write-Host "⚠️  Todas as ações serão registradas em log de auditoria`n" -ForegroundColor Yellow
		
		# ✅ LOG DE SEGURANÇA OBRIGATÓRIO
		$AutomationContext = @"
EXECUÇÃO AUTOMATIZADA DETECTADA
================================
Parâmetro -Force: ATIVADO
Total de usuários: $TotalUsers
Data/Hora: $($DateFormat.Display)
Usuário do sistema: $($env:USERNAME)
Máquina: $($env:COMPUTERNAME)
Domínio: $($env:USERDNSDOMAIN)
Processo ID: $PID
Contexto: $(if ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name -like "*SYSTEM*") { "Task Scheduler/Service" }
			else { "Execução manual com -Force" })

ATENÇÃO: Esta operação bypassa confirmação manual!
Todas as exclusões serão registradas individualmente.
================================
"@
		
		Write-SecurityAuditLog -Message $AutomationContext -Severity "Warning"
		
		# Pausa de 3 segundos para permitir cancelamento (Ctrl+C)
		Write-Host "Iniciando em 3 segundos... (Ctrl+C para cancelar)" -ForegroundColor Yellow
		Start-Sleep -Seconds 3
	}
	
	Write-Host "`n⚙️  Processando exclusões...`n" -ForegroundColor Yellow
	
	# ========================================================================
	# INICIALIZAÇÃO DO LOG DE EXCLUSÃO
	# ========================================================================
	
	$LogHeader = @"
╔════════════════════════════════════════════════════════════════════════════╗
║                        LOG DE EXCLUSÃO DE USUÁRIOS                         ║
╚════════════════════════════════════════════════════════════════════════════╝

INÍCIO DA EXCLUSÃO: $($DateFormat.Display)
Total de usuários a excluir: $TotalUsers
Modo de execução: $(if ($Force) { "AUTOMATIZADO (-Force)" }
		else { "MANUAL (com confirmação)" })
Operador: $($env:USERNAME)@$($env:COMPUTERNAME)

════════════════════════════════════════════════════════════════════════════

"@
	
	$LogHeader | Out-File -FilePath $FilePaths.DeletionLog -Encoding UTF8
	
	# ========================================================================
	# PROCESSAMENTO DAS EXCLUSÕES
	# ========================================================================
	
	$ProcessedCount = 0
	
	foreach ($User in $AuditData)
	{
		$ProcessedCount++
		$PercentComplete = [math]::Round(($ProcessedCount / $TotalUsers) * 100, 2)
		
		Write-Progress -Activity "Excluindo usuários" `
					   -Status "Processando $ProcessedCount de $TotalUsers ($PercentComplete%)" `
					   -PercentComplete $PercentComplete
		
		try
		{
			Write-Host "[$ProcessedCount/$TotalUsers] Excluindo: $($User.Login)" -ForegroundColor Cyan
			
			# ✅ EXCLUSÃO DO OBJETO AD
			Remove-ADObject -Identity $User.DN -Confirm:$false -ErrorAction Stop
			
			$SuccessCount++
			Write-Host "  ✓ Excluído com sucesso" -ForegroundColor Green
			
			# ✅ LOG DE SUCESSO
			$SuccessLog = "SUCESSO | $($User.Login) | $($User.Nome) | DN: $($User.DN) | $($DateFormat.Display)"
			$SuccessLog | Out-File -FilePath $FilePaths.DeletionLog -Append -Encoding UTF8
			
			# ✅ LOG DE SEGURANÇA (se -Force)
			if ($Force)
			{
				Write-SecurityAuditLog -Message "Usuário excluído (Force): $($User.Login) - $($User.Nome)" -Severity "Warning"
			}
		}
		catch
		{
			$ErrorCount++
			Write-Host "  ✗ Erro: $_" -ForegroundColor Red
			
			# ✅ LOG DE ERRO
			$ErrorLog = "ERRO | $($User.Login) | $($User.Nome) | Erro: $_ | $($DateFormat.Display)"
			$ErrorLog | Out-File -FilePath $FilePaths.DeletionLog -Append -Encoding UTF8
			$_ | Out-File -FilePath $FilePaths.ErrorLog -Append -Encoding UTF8
			
			# ✅ LOG DE SEGURANÇA (erro crítico)
			Write-SecurityAuditLog -Message "FALHA ao excluir usuário: $($User.Login) - Erro: $_" -Severity "Critical"
		}
	}
	
	Write-Progress -Activity "Excluindo usuários" -Completed
	
	# ========================================================================
	# FINALIZAÇÃO DO LOG
	# ========================================================================
	
	$LogFooter = @"

════════════════════════════════════════════════════════════════════════════

FIM DA EXCLUSÃO: $($DateFormat.Display)
Duração: $((New-TimeSpan -Start $Timestamp -End (Get-Date)).TotalSeconds) segundos

RESULTADOS:
- Sucessos: $SuccessCount
- Erros: $ErrorCount
- Total processado: $ProcessedCount

Modo de execução: $(if ($Force) { "AUTOMATIZADO (-Force)" }
		else { "MANUAL" })
Operador: $($env:USERNAME)

════════════════════════════════════════════════════════════════════════════
"@
	
	$LogFooter | Out-File -FilePath $FilePaths.DeletionLog -Append -Encoding UTF8
	
	Write-Host "`n✓ Processo de exclusão finalizado" -ForegroundColor Green
	
	# ✅ LOG DE SEGURANÇA FINAL
	Write-SecurityAuditLog -Message "Processo de exclusão concluído. Sucessos: $SuccessCount, Erros: $ErrorCount" -Severity "Info"
	
	return @{
		Success   = $SuccessCount
		Errors    = $ErrorCount
		Cancelled = $false
	}
}

# ============================================================================
# FUNÇÕES DE EMAIL
# ============================================================================

function Send-AuditEmail
{
    <#
    .SYNOPSIS
        Envia email HTML formatado com relatório de auditoria.

    .DESCRIPTION
        Cria email HTML profissional com estatísticas, alertas e anexos.
        Versão 3.3: Inclui indicação de execução com -Force no email.
    #>
	param (
		[Parameter(Mandatory)]
		[AuditStatistics]$Statistics,
		[Parameter(Mandatory)]
		[array]$Attachments,
		[Parameter(Mandatory = $false)]
		[hashtable]$DeletionResults,
		[Parameter(Mandatory = $false)]
		[switch]$WasForced
	)
	
	Write-Host "`n📧 Enviando relatório por email..." -ForegroundColor Yellow
	
	# Construção do corpo do email (HTML)
	$EmailBody = @"
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f4f4; margin: 0; padding: 20px; }
        .container { max-width: 800px; margin: 0 auto; background-color: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #0078D4 0%, #005A9E 100%); color: white; padding: 30px; border-radius: 8px 8px 0 0; text-align: center; }
        .header h1 { margin: 0; font-size: 28px; }
        .content { padding: 30px; }
        .stats-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 20px; margin: 20px 0; }
        .stat-card { background-color: #f8f9fa; padding: 20px; border-radius: 5px; border-left: 4px solid #0078D4; }
        .stat-card h3 { margin: 0 0 10px 0; color: #333; font-size: 14px; text-transform: uppercase; }
        .stat-card .number { font-size: 32px; font-weight: bold; color: #0078D4; }
        .alert { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .alert.danger { background-color: #f8d7da; border-left-color: #dc3545; }
        .alert.success { background-color: #d4edda; border-left-color: #28a745; }
        .alert.warning { background-color: #fff3cd; border-left-color: #ffc107; }
        .section { margin: 30px 0; }
        .section h2 { color: #0078D4; border-bottom: 2px solid #0078D4; padding-bottom: 10px; }
        .footer { background-color: #f8f9fa; padding: 20px 30px; border-radius: 0 0 8px 8px; text-align: center; font-size: 12px; color: #666; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #0078D4; color: white; }
        tr:hover { background-color: #f5f5f5; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 Relatório de Auditoria</h1>
            <p style="margin: 10px 0 0 0; font-size: 16px;">Usuários Desativados - $($Config.Company)</p>
        </div>

        <div class="content">
            <div class="section">
                <h2>Informações da Execução</h2>
                <p><strong>Data/Hora:</strong> $($DateFormat.Display)</p>
                <p><strong>OU Auditada:</strong> $($Config.SearchBase)</p>
                <p><strong>Operação:</strong> $Operation</p>
                <p><strong>Versão do Script:</strong> 3.3 (Produção com Automação)</p>
"@
	
	# ✅ INDICAÇÃO DE EXECUÇÃO AUTOMATIZADA
	if ($WasForced)
	{
		$EmailBody += @"
                <p><strong>Modo de Execução:</strong> <span style="color: #dc3545; font-weight: bold;">🤖 AUTOMATIZADO (-Force)</span></p>
"@
	}
	else
	{
		$EmailBody += @"
                <p><strong>Modo de Execução:</strong> Manual (com confirmação)</p>
"@
	}
	
	$EmailBody += @"
            </div>

            <div class="section">
                <h2>Estatísticas Gerais</h2>
                <div class="stats-grid">
                    <div class="stat-card">
                        <h3>Total de Usuários</h3>
                        <div class="number">$($Statistics.TotalUsuarios)</div>
                    </div>
                    <div class="stat-card">
                        <h3>Usuários Desabilitados</h3>
                        <div class="number">$($Statistics.UsuariosDesabilitados)</div>
                    </div>
                    <div class="stat-card">
                        <h3>Sem Logon</h3>
                        <div class="number">$($Statistics.UsuariosSemLogon)</div>
                    </div>
                    <div class="stat-card">
                        <h3>Inativos +90 dias</h3>
                        <div class="number">$($Statistics.UsuariosInativos90Dias)</div>
                    </div>
                </div>
            </div>
"@
	
	# Adiciona informações de exclusão se aplicável
	if ($DeletionResults)
	{
		if ($DeletionResults.Cancelled)
		{
			$EmailBody += @"
            <div class="alert">
                <strong>⚠️ Operação Cancelada</strong><br>
                A exclusão de usuários foi cancelada pelo operador.
            </div>
"@
		}
		else
		{
			$AlertClass = if ($DeletionResults.Errors -gt 0) { "danger" }
			else { "success" }
			$EmailBody += @"
            <div class="section">
                <h2>Resultado da Exclusão</h2>
                <div class="alert $AlertClass">
                    <strong>Exclusões Realizadas</strong><br>
                    ✓ Sucessos: $($DeletionResults.Success)<br>
                    ✗ Erros: $($DeletionResults.Errors)
                </div>
"@
			
			# ✅ ALERTA ADICIONAL SE FOI -Force
			if ($WasForced)
			{
				$EmailBody += @"
                <div class="alert warning">
                    <strong>⚠️ ATENÇÃO:</strong> Esta exclusão foi executada em modo automatizado (-Force) sem confirmação manual.
                    Todas as ações foram registradas em log de auditoria de segurança.
                </div>
"@
			}
			
			$EmailBody += @"
            </div>
"@
		}
	}
	
	# Alertas de segurança
	$EmailBody += @"
            <div class="section">
                <h2>Alertas de Segurança</h2>
"@
	
	if ($Statistics.UsuariosComSenhaExpirada -gt 0)
	{
		$EmailBody += @"
                <div class="alert danger">
                    <strong>⚠️ Senhas Expiradas:</strong> $($Statistics.UsuariosComSenhaExpirada) usuário(s) com senha expirada
                </div>
"@
	}
	
	if ($Statistics.UsuariosSemLogon -gt 0)
	{
		$EmailBody += @"
                <div class="alert">
                    <strong>⚠️ Sem Logon:</strong> $($Statistics.UsuariosSemLogon) usuário(s) nunca logaram no sistema
                </div>
"@
	}
	
	# Distribuição por departamento
	if ($Statistics.UsuariosPorDepartamento.Count -gt 0)
	{
		$EmailBody += @"
            </div>

            <div class="section">
                <h2>Distribuição por Departamento</h2>
                <table>
                    <tr>
                        <th>Departamento</th>
                        <th>Quantidade</th>
                    </tr>
"@
		$Statistics.UsuariosPorDepartamento.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
			$EmailBody += @"
                    <tr>
                        <td>$($_.Key)</td>
                        <td>$($_.Value)</td>
                    </tr>
"@
		}
		$EmailBody += @"
                </table>
            </div>
"@
	}
	
	# Distribuição por empresa (se aplicável)
	if ($Statistics.UsuariosPorEmpresa.Count -gt 0 -and $Statistics.UsuariosPorEmpresa.Count -gt 1)
	{
		$EmailBody += @"
            <div class="section">
                <h2>Distribuição por Empresa</h2>
                <table>
                    <tr>
                        <th>Empresa</th>
                        <th>Quantidade</th>
                    </tr>
"@
		$Statistics.UsuariosPorEmpresa.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
			$EmailBody += @"
                    <tr>
                        <td>$($_.Key)</td>
                        <td>$($_.Value)</td>
                    </tr>
"@
		}
		$EmailBody += @"
                </table>
            </div>
"@
	}
	
	# Rodapé
	$EmailBody += @"
        </div>

        <div class="footer">
            <p>Este é um email automático gerado pelo sistema de auditoria do Active Directory.</p>
            <p>Os arquivos detalhados estão anexados a este email para análise completa.</p>
            <p>Em caso de dúvidas, entre em contato com a equipe de infraestrutura.</p>
            <hr style="margin: 15px 0; border: none; border-top: 1px solid #ddd;">
            <p style="font-size: 10px; color: #999;">
                Script versão 3.3 - Sistema de Auditoria GlobalHitss<br>
                Executado em: $($DateFormat.Display)
            </p>
        </div>
    </div>
</body>
</html>
"@
	
	# Parâmetros do email
	$EmailParams = @{
		From	    = $Config.EmailFrom
		To		    = $Config.EmailTo
		Subject	    = "[$($Config.Company)] Auditoria de Usuários Desativados - $($DateFormat.ShortDate)"
		Body	    = $EmailBody
		BodyAsHtml  = $true
		Attachments = $Attachments
		SmtpServer  = $Config.SMTPServer
		Port	    = $Config.SMTPPort
		Encoding    = [System.Text.Encoding]::UTF8
	}
	
	# Adiciona CC se configurado
	if ($Config.EmailCC.Count -gt 0)
	{
		$EmailParams.Add('Cc', $Config.EmailCC)
	}
	
	try
	{
		Send-MailMessage @EmailParams
		Write-Host "  ✓ Email enviado com sucesso" -ForegroundColor Green
		Write-Host "  ✓ Destinatários: $($Config.EmailTo -join ', ')" -ForegroundColor Green
		if ($Config.EmailCC.Count -gt 0)
		{
			Write-Host "  ✓ Cópia para: $($Config.EmailCC -join ', ')" -ForegroundColor Green
		}
		Write-Host "`n" -ForegroundColor Green
		
		# Log de sucesso do email
		Write-SecurityAuditLog -Message "Email de relatório enviado com sucesso" -Severity "Info"
		
		return $true
	}
	catch
	{
		Write-Warning "Falha ao enviar email: $_"
		$_ | Out-File -FilePath $FilePaths.ErrorLog -Append -Encoding UTF8
		
		# Log de falha do email
		Write-SecurityAuditLog -Message "Falha no envio de email: $_" -Severity "Warning"
		
		return $false
	}
}

# ============================================================================
# FUNÇÃO PRINCIPAL (ATUALIZADA PARA v3.3)
# ============================================================================

function Start-DisabledUsersManagement
{
    <#
    .SYNOPSIS
        Função principal que orquestra todo o processo de auditoria e gestão.

    .DESCRIPTION
        Executa o fluxo completo baseado nos parâmetros Operation, ExportFormat e Force:
        1. Inicialização do ambiente
        2. Validação de conectividade AD
        3. Auditoria de usuários
        4. Cálculo de estatísticas
        5. Exportação de dados
        6. Exclusão (se aplicável, com suporte a -Force)
        7. Envio de email
        8. Relatório final

    .OUTPUTS
        Nenhum - Exibe progresso na tela e gera arquivos

    .EXAMPLE
        # Execução manual segura
        Start-DisabledUsersManagement -Operation Audit

        # Execução automatizada
        Start-DisabledUsersManagement -Operation Delete -Force:$true
    #>
	param (
		[Parameter(Mandatory = $false)]
		[switch]$Force
	)
	
	# Banner inicial (atualizado para v3.3)
	Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
	Write-Host "║                                                                ║" -ForegroundColor Cyan
	Write-Host "║        SISTEMA DE AUDITORIA E GESTÃO DE USUÁRIOS AD            ║" -ForegroundColor Cyan
	Write-Host "║                    GlobalHitss - v3.3                          ║" -ForegroundColor Cyan
	Write-Host "║              (Produção com Automação -Force)                   ║" -ForegroundColor Cyan
	Write-Host "║                                                                ║" -ForegroundColor Cyan
	Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
	
	# ✅ INDICAÇÃO DE MODO DE EXECUÇÃO
	Write-Host "`nOperação selecionada: $Operation" -ForegroundColor White
	Write-Host "Formato de exportação: $ExportFormat" -ForegroundColor White
	Write-Host "Modo de execução: $(if ($Force) { '🤖 AUTOMATIZADO (-Force)' }
		else { '👤 MANUAL (Seguro)' })" -ForegroundColor $(if ($Force) { "Yellow" }
		else { "Green" })
	Write-Host "OU alvo: $($Config.SearchBase)" -ForegroundColor White
	Write-Host "Data/Hora: $($DateFormat.Display)`n" -ForegroundColor White
	
	# ========================================================================
	# INICIALIZAÇÃO
	# ========================================================================
	
	Initialize-Environment
	
	# ========================================================================
	# VALIDAÇÕES
	# ========================================================================
	
	if (-not (Test-ADConnection))
	{
		Write-Error "Falha na validação do Active Directory"
		exit 1
	}
	
	if (-not (Test-OUExists -OUPath $Config.SearchBase))
	{
		Write-Error "OU não encontrada"
		exit 1
	}
	
	# ========================================================================
	# AUDITORIA
	# ========================================================================
	
	Write-Host "🚀 Iniciando processo de auditoria..." -ForegroundColor Cyan
	$AuditData = Get-DisabledUsersAudit
	
	if ($null -eq $AuditData -or $AuditData.Count -eq 0)
	{
		Write-Host "⚠️  Nenhum dado para processar. Encerrando.`n" -ForegroundColor Yellow
		exit 0
	}
	
	# ========================================================================
	# ESTATÍSTICAS
	# ========================================================================
	
	$Statistics = Get-AuditStatistics -AuditData $AuditData
	
	# ========================================================================
	# EXPORTAÇÃO
	# ========================================================================
	
	Write-Host "📦 EXPORTANDO DADOS" -ForegroundColor Cyan
	Write-Host "========================================`n" -ForegroundColor Cyan
	
	$ExportedFiles = @()
	
	# CSV sempre é exportado
	if (Export-AuditToCSV -AuditData $AuditData -FilePath $FilePaths.AuditCSV)
	{
		$ExportedFiles += $FilePaths.AuditCSV
	}
	
	# Exportações adicionais baseadas no parâmetro
	switch ($ExportFormat)
	{
		"Excel" {
			if (Export-AuditToExcelReady -AuditData $AuditData -FilePath $FilePaths.AuditExcel)
			{
				$ExportedFiles += $FilePaths.AuditExcel
			}
		}
		"JSON" {
			if (Export-AuditToJSON -AuditData $AuditData -FilePath $FilePaths.AuditJSON -Statistics $Statistics)
			{
				$ExportedFiles += $FilePaths.AuditJSON
			}
		}
		"All" {
			if (Export-AuditToExcelReady -AuditData $AuditData -FilePath $FilePaths.AuditExcel)
			{
				$ExportedFiles += $FilePaths.AuditExcel
			}
			if (Export-AuditToJSON -AuditData $AuditData -FilePath $FilePaths.AuditJSON -Statistics $Statistics)
			{
				$ExportedFiles += $FilePaths.AuditJSON
			}
		}
	}
	
	# Relatório resumido sempre é gerado
	Export-SummaryReport -Statistics $Statistics -FilePath $FilePaths.SummaryReport
	$ExportedFiles += $FilePaths.SummaryReport
	
	# ========================================================================
	# EXCLUSÃO (SE APLICÁVEL - COM SUPORTE A -Force)
	# ========================================================================
	
	$DeletionResults = $null
	$WasForced = $Force # Para passar ao email
	
	if ($Operation -in @("Delete", "Both"))
	{
		Write-Host "`n🗑️  Modo de exclusão ativado" -ForegroundColor Yellow
		
		# ✅ CHAMA FUNÇÃO COM PARÂMETRO -Force
		$DeletionResults = Remove-AuditedUsers -AuditData $AuditData -Force:$Force
		
		if (-not $DeletionResults.Cancelled)
		{
			$ExportedFiles += $FilePaths.DeletionLog
			$ExportedFiles += $FilePaths.SecurityLog # Log de segurança
		}
	}
	
	# ========================================================================
	# ENVIO DE EMAIL
	# ========================================================================
	
	Write-Host "📧 Preparando notificação por email..." -ForegroundColor Cyan
	$EmailSuccess = Send-AuditEmail -Statistics $Statistics -Attachments $ExportedFiles -DeletionResults $DeletionResults -WasForced:$WasForced
	
	# ========================================================================
	# RESUMO FINAL
	# ========================================================================
	
	Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
	Write-Host "║                    EXECUÇÃO FINALIZADA                         ║" -ForegroundColor Cyan
	Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
	
	Write-Host "`n📊 RESUMO DA EXECUÇÃO:" -ForegroundColor White
	Write-Host "  • Usuários auditados: $($Statistics.TotalUsuarios)" -ForegroundColor White
	Write-Host "  • Usuários desabilitados: $($Statistics.UsuariosDesabilitados)" -ForegroundColor White
	Write-Host "  • Usuários sem logon: $($Statistics.UsuariosSemLogon)" -ForegroundColor White
	Write-Host "  • Inativos há +90 dias: $($Statistics.UsuariosInativos90Dias)" -ForegroundColor White
	Write-Host "  • Arquivos gerados: $($ExportedFiles.Count)" -ForegroundColor White
	
	if ($EmailSuccess)
	{
		Write-Host "  • Email enviado: ✓ Sucesso" -ForegroundColor Green
	}
	else
	{
		Write-Host "  • Email enviado: ✗ Falha (verifique logs)" -ForegroundColor Red
	}
	
	if ($DeletionResults -and -not $DeletionResults.Cancelled)
	{
		Write-Host "`n🗑️  RESULTADO DA EXCLUSÃO:" -ForegroundColor White
		Write-Host "  • Exclusões bem-sucedidas: $($DeletionResults.Success)" -ForegroundColor Green
		if ($DeletionResults.Errors -gt 0)
		{
			Write-Host "  • Erros na exclusão: $($DeletionResults.Errors)" -ForegroundColor Red
		}
		else
		{
			Write-Host "  • Erros na exclusão: 0" -ForegroundColor Green
		}
		
		# ✅ INDICAÇÃO DE MODO DE EXECUÇÃO
		if ($WasForced)
		{
			Write-Host "  • Modo de execução: 🤖 AUTOMATIZADO (-Force)" -ForegroundColor Yellow
			Write-Host "  • Logs de segurança: $FilePaths.SecurityLog" -ForegroundColor Yellow
		}
		else
		{
			Write-Host "  • Modo de execução: 👤 MANUAL (com confirmação)" -ForegroundColor Green
		}
	}
	
	Write-Host "`n📁 ARQUIVOS GERADOS:" -ForegroundColor White
	foreach ($File in $ExportedFiles)
	{
		$FileName = Split-Path $File -Leaf
		$FileSize = if (Test-Path $File)
		{
			[math]::Round((Get-Item $File).Length / 1KB, 2)
		}
		else
		{
			"N/A"
		}
		Write-Host "  • $FileName ($FileSize KB)" -ForegroundColor Gray
	}
	
	Write-Host "`n📍 LOCALIZAÇÃO DOS ARQUIVOS:" -ForegroundColor White
	Write-Host "  • Exportações: $($Config.ExportDirectory)" -ForegroundColor Gray
	Write-Host "  • Logs: $($Config.LogDirectory)" -ForegroundColor Gray
	
	if ($Operation -in @("Delete", "Both") -and $DeletionResults -and -not $DeletionResults.Cancelled)
	{
		Write-Host "`n⚠️  ATENÇÃO: $($DeletionResults.Success) usuário(s) foram EXCLUÍDOS permanentemente!" -ForegroundColor Red
		Write-Host "   Consulte o log de exclusão para detalhes." -ForegroundColor Red
		
		if ($WasForced)
		{
			Write-Host "   ⚠️  Esta foi uma execução AUTOMATIZADA (-Force)!" -ForegroundColor Red
			Write-Host "   Log de segurança: $FilePaths.SecurityLog" -ForegroundColor Red
		}
	}
	
	Write-Host "`n✓ Processo concluído com sucesso!`n" -ForegroundColor Green
	Write-Host "Para suporte técnico, contate: n3-vm-so@globalhitss.com.br" -ForegroundColor Cyan
}

# ============================================================================
# EXECUÇÃO PRINCIPAL (ATUALIZADA PARA v3.3)
# ============================================================================

# Bloco try-catch global para capturar erros não tratados
try
{
	# ========================================================================
	# VALIDAÇÃO DE SEGURANÇA PARA -Force
	# ========================================================================
	
	if ($Force -and ($Operation -eq "Delete" -or $Operation -eq "Both"))
	{
		# ✅ VALIDAÇÃO DE SEGURANÇA OBRIGATÓRIA
		
		# Verifica se está rodando como SYSTEM (Task Scheduler)
		$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
		$IsSystemAccount = $CurrentUser -like "*SYSTEM*" -or $CurrentUser -like "*NETWORK SERVICE*"
		
		# Verifica horário (opcional - configurável)
		$CurrentHour = (Get-Date).Hour
		$IsBusinessHours = $CurrentHour -ge 8 -and $CurrentHour -le 18
		$AllowBusinessHours = $Config.AllowForceInBusinessHours
		
		# Log inicial de segurança
		$SecurityContext = @"
VALIDAÇÃO DE SEGURANÇA -Force DETECTADA
=======================================
Data/Hora: $($DateFormat.Display)
Operação: $Operation
Parâmetro -Force: ATIVADO
Usuário atual: $CurrentUser
Máquina: $($env:COMPUTERNAME)
Horário: $CurrentHour:00 (Business Hours: $IsBusinessHours)

CONTEXTO DE EXECUÇÃO:
- Conta SYSTEM: $IsSystemAccount
- Permitir horário comercial: $AllowBusinessHours

STATUS: $(if ($IsSystemAccount -or (-not $IsBusinessHours -or $AllowBusinessHours)) { "APROVADO" }
			else { "BLOQUEADO" })
=======================================
"@
		
		Write-SecurityAuditLog -Message $SecurityContext -Severity "Warning"
		
		# ✅ BLOQUEIO DE SEGURANÇA (se necessário)
		if (-not $IsSystemAccount -and $IsBusinessHours -and -not $AllowBusinessHours)
		{
			Write-Error @"
❌ EXECUÇÃO BLOQUEADA POR SEGURANÇA

Parâmetro -Force detectado em:
- Conta de usuário manual ($CurrentUser)
- Horário comercial ($CurrentHour:00)
- Configuração: AllowForceInBusinessHours = False

Para permitir:
1. Execute como SYSTEM (Task Scheduler)
2. Configure AllowForceInBusinessHours = $true
3. Execute fora do horário comercial (19h-8h)

Consulte: $FilePaths.SecurityLog
"@
			exit 1
		}
		
		Write-Host "✅ Validação de segurança aprovada para -Force" -ForegroundColor Green
	}
	
	# ========================================================================
	# VALIDAÇÃO INICIAL DOS PARÂMETROS
	# ========================================================================
	
	if (($Operation -eq "Delete" -or $Operation -eq "Both") -and -not $Force)
	{
		# ✅ MODO MANUAL: Confirmação adicional
		Write-Host "⚠️  MODO DE EXCLUSÃO ATIVADO (MANUAL)" -ForegroundColor Yellow
		Write-Host "Esta operação remove usuários permanentemente do Active Directory!" -ForegroundColor Yellow
		$ConfirmDelete = Read-Host "Você tem certeza que deseja continuar? (S/N)"
		if ($ConfirmDelete -ne "S")
		{
			Write-Host "Operação cancelada pelo usuário." -ForegroundColor Yellow
			exit 0
		}
	}
	
	# ========================================================================
	# EXECUTA O PROCESSO PRINCIPAL
	# ========================================================================
	
	Start-DisabledUsersManagement -Force:$Force
}
catch
{
	# ========================================================================
	# TRATAMENTO DE ERRO CRÍTICO
	# ========================================================================
	
	Write-Host "`n❌ ERRO CRÍTICO" -ForegroundColor Red
	Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
	Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red
	Write-Host "Linha: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
	Write-Host "Comando: $($_.InvocationInfo.Line.Trim())" -ForegroundColor Red
	
	# Log do erro crítico
	$ErrorDetails = @"
ERRO CRÍTICO - $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
Script: Manage-DisabledUsers.ps1
Versão: 3.3
Operação: $Operation
ExportFormat: $ExportFormat
Force: $(if ($Force) { "ATIVADO" }
		else { "DESATIVADO" })

DETALHES DO ERRO:
Tipo: $($_.Exception.GetType().Name)
Mensagem: $($_.Exception.Message)
StackTrace: $($_.Exception.StackTrace)

CONTEXTO:
Usuário: $($env:USERNAME)
Máquina: $($env:COMPUTERNAME)
Domínio: $env:USERDNSDOMAIN
Processo ID: $PID

PARÂMETROS:
Operation: $Operation
ExportFormat: $ExportFormat
SearchBase: $($Config.SearchBase)
Force: $(if ($Force) { "True" }
		else { "False" })

"@
	
	$ErrorDetails | Out-File -FilePath $FilePaths.ErrorLog -Encoding UTF8
	Write-SecurityAuditLog -Message "ERRO CRÍTICO: $($_.Exception.Message)" -Severity "Critical"
	
	Write-Host "`nDetalhes do erro salvos em:" -ForegroundColor Yellow
	Write-Host "  • Log geral: $FilePaths.ErrorLog" -ForegroundColor Yellow
	Write-Host "  • Log de segurança: $FilePaths.SecurityLog" -ForegroundColor Yellow
	
	exit 1
}
finally
{
	# ========================================================================
	# LIMPEZA FINAL
	# ========================================================================
	
	# Restaura configuração padrão
	if ($ErrorActionPreference -eq "Stop")
	{
		$ErrorActionPreference = "Continue"
	}
	
	# Log final de execução
	Write-SecurityAuditLog -Message "Script finalizado. Status: $(if ($LASTEXITCODE -eq 0) { 'SUCESSO' }
		else { 'ERRO' })" -Severity "Info"
}

# ============================================================================
# FIM DO SCRIPT
# ============================================================================

Write-Host "`nScript Manage-DisabledUsers.ps1 v3.3 finalizado." -ForegroundColor Gray
Write-Host "GlobalHitss - Infraestrutura de TI" -ForegroundColor Gray
Write-Host "Contato: n3-vm-so@globalhitss.com.br" -ForegroundColor Gray

# ============================================================================
# FIM DO CÓDIGO
# ============================================================================
