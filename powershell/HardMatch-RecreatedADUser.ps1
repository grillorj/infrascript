<#
.SYNOPSIS
  Hard Match: usuário já existe no Entra ID e foi recriado no AD (novo ObjectGUID).
  Atualiza onPremisesImmutableId (ImmutableID) no Entra ID para o Base64 do novo GUID do AD.

.PARAMETER CloudUPN
  UPN do usuário no Entra (ex: joao.silva@empresa.com.br)

.PARAMETER AdIdentity
  Identidade para localizar o usuário no AD (SamAccountName, UPN, DN, etc.)

.PARAMETER Force
  Se definido, executa a alteração. Sem -Force o script roda em modo simulação.

.EXAMPLE
  .\HardMatch-RecreatedADUser.ps1 -CloudUPN "joao@empresa.com.br" -AdIdentity "joao" -Force
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[Parameter(Mandatory)]
	[string]$CloudUPN,
	[Parameter(Mandatory)]
	[string]$AdIdentity,
	[switch]$Force
)

function Convert-GuidToImmutableIdBase64
{
	param ([Parameter(Mandatory)]
		[Guid]$Guid)
	return [Convert]::ToBase64String($Guid.ToByteArray())
}

function Require-Module
{
	param ([Parameter(Mandatory)]
		[string]$Name)
	if (-not (Get-Module -ListAvailable -Name $Name))
	{
		throw "Módulo '$Name' não encontrado. Instale/importe antes de executar."
	}
}

try
{
	# ----------------------------
	# 1) Pré-requisitos
	# ----------------------------
	Require-Module -Name ActiveDirectory
	if (-not (Get-Module Microsoft.Graph.Users -ListAvailable))
	{
		Write-Host "Instalando Microsoft.Graph..." -ForegroundColor Yellow
		Install-Module Microsoft.Graph -Scope CurrentUser -Force
	}
	
	Import-Module ActiveDirectory -ErrorAction Stop
	Import-Module Microsoft.Graph.Users -ErrorAction Stop
	
	# ----------------------------
	# 2) Busca usuário no AD e gera novo ImmutableID (Base64 do ObjectGUID)
	# ----------------------------
	$adUser = Get-ADUser -Identity $AdIdentity -Properties ObjectGUID, UserPrincipalName, SamAccountName, DistinguishedName -ErrorAction Stop
	$newGuid = [Guid]$adUser.ObjectGUID
	$newImmutableId = Convert-GuidToImmutableIdBase64 -Guid $newGuid
	
	Write-Host "=== AD (novo usuário recriado) ===" -ForegroundColor Cyan
	Write-Host ("SamAccountName:     {0}" -f $adUser.SamAccountName)
	Write-Host ("UPN (AD):           {0}" -f $adUser.UserPrincipalName)
	Write-Host ("DN:                {0}" -f $adUser.DistinguishedName)
	Write-Host ("ObjectGUID:         {0}" -f $newGuid)
	Write-Host ("ImmutableID (Base64): {0}" -f $newImmutableId)
	Write-Host ""
	
	# ----------------------------
	# 3) Conecta no Graph e lê usuário no Entra
	# ----------------------------
	$scopes = @("User.ReadWrite.All", "Directory.ReadWrite.All")
	Connect-MgGraph -Scopes $scopes | Out-Null
	
	$cloudUser = Get-MgUser -UserId $CloudUPN -Property "id,displayName,userPrincipalName,onPremisesImmutableId,onPremisesSyncEnabled" -ErrorAction Stop
	
	Write-Host "=== Entra ID (usuário existente) ===" -ForegroundColor Cyan
	Write-Host ("DisplayName:        {0}" -f $cloudUser.DisplayName)
	Write-Host ("UPN (Entra):        {0}" -f $cloudUser.UserPrincipalName)
	Write-Host ("OnPremisesSyncEnabled: {0}" -f $cloudUser.OnPremisesSyncEnabled)
	Write-Host ("ImmutableID atual:  {0}" -f $cloudUser.OnPremisesImmutableId)
	Write-Host ""
	
	# ----------------------------
	# 4) Validações de segurança
	# ----------------------------
	if ($cloudUser.OnPremisesSyncEnabled -eq $true)
	{
		Write-Host "ATENÇÃO: Este usuário parece estar com sincronização ativa (onPremisesSyncEnabled=True)." -ForegroundColor Yellow
		Write-Host "Normalmente, o ImmutableID é controlado pelo AAD Connect. Avalie corrigir pelo AD/AAD Connect." -ForegroundColor Yellow
		Write-Host "Ainda assim, vou continuar mostrando o que seria feito (modo simulação), mas pode falhar ao aplicar." -ForegroundColor Yellow
		Write-Host ""
	}
	
	if ($cloudUser.OnPremisesImmutableId -eq $newImmutableId)
	{
		Write-Host "Nada a fazer: o ImmutableID no Entra já é igual ao do novo usuário no AD." -ForegroundColor Green
		return
	}
	
	# ----------------------------
	# 5) Estratégia recomendada:
	#    - Se já existe ImmutableID antigo, limpar primeiro
	#    - Aplicar o novo ImmutableID
	# ----------------------------
	$willApply = $Force.IsPresent
	
	if (-not $willApply)
	{
		Write-Host "MODO SIMULAÇÃO: execute com -Force para aplicar." -ForegroundColor Yellow
	}
	
	# 5.1) Limpa ImmutableID antigo (se existir)
	if ($cloudUser.OnPremisesImmutableId)
	{
		$msg1 = "Limpar ImmutableID antigo do usuário $CloudUPN (setar null)"
		if ($PSCmdlet.ShouldProcess($CloudUPN, $msg1))
		{
			if ($willApply)
			{
				Update-MgUser -UserId $CloudUPN -OnPremisesImmutableId $null -ErrorAction Stop
				Write-Host "OK: ImmutableID antigo removido (null)." -ForegroundColor Green
			}
			else
			{
				Write-Host "SIMULAÇÃO: Update-MgUser -OnPremisesImmutableId `$null" -ForegroundColor DarkYellow
			}
		}
	}
	else
	{
		Write-Host "ImmutableID atual está vazio/null. Não precisa limpar." -ForegroundColor Gray
	}
	
	# Pequena pausa para consistência (opcional)
	Start-Sleep -Seconds 2
	
	# 5.2) Define novo ImmutableID
	$msg2 = "Definir novo ImmutableID do AD no usuário $CloudUPN"
	if ($PSCmdlet.ShouldProcess($CloudUPN, $msg2))
	{
		if ($willApply)
		{
			Update-MgUser -UserId $CloudUPN -OnPremisesImmutableId $newImmutableId -ErrorAction Stop
			Write-Host "OK: Novo ImmutableID aplicado." -ForegroundColor Green
		}
		else
		{
			Write-Host "SIMULAÇÃO: Update-MgUser -OnPremisesImmutableId '$newImmutableId'" -ForegroundColor DarkYellow
		}
	}
	
	# ----------------------------
	# 6) Validação final
	# ----------------------------
	Start-Sleep -Seconds 2
	$check = Get-MgUser -UserId $CloudUPN -Property "onPremisesImmutableId,onPremisesSyncEnabled" -ErrorAction Stop
	
	Write-Host ""
	Write-Host "=== Validação ===" -ForegroundColor Cyan
	Write-Host ("OnPremisesSyncEnabled: {0}" -f $check.OnPremisesSyncEnabled)
	Write-Host ("ImmutableID agora:      {0}" -f $check.OnPremisesImmutableId)
	
	if ($willApply -and $check.OnPremisesImmutableId -ne $newImmutableId)
	{
		Write-Host "ALERTA: O ImmutableID retornado não bate com o esperado. Pode ser delay ou bloqueio por sync." -ForegroundColor Yellow
	}
}
catch
{
	Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
	throw
}
finally
{
	Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
