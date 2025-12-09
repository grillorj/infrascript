<#
.SYNOPSIS
    Adiciona usuários a múltiplos grupos do Active Directory e gera relatório de evidência.

.DESCRIPTION
    Script que lê usuários e grupos de um arquivo de configuração e adiciona os usuários
    aos grupos especificados, gerando um relatório CSV com o resultado das operações.

.NOTES
    Autor: Leonardo Grillo
    Requer: Módulo ActiveDirectory

    Exemplo de arquivo config.txt:
        Users=user1;user2;user3
        Groups=GroupA;GroupB;GroupC
#>

# Importa o módulo do Active Directory
Import-Module ActiveDirectory -ErrorAction Stop

# Carrega configurações do arquivo
$ConfigFile = "C:\Scripts\PS1\config.txt" #Ajuste o local do arquivo

if (-not (Test-Path $ConfigFile)) {
    Write-Host "ERRO: Arquivo de configuração não encontrado: $ConfigFile" -ForegroundColor Red
    exit 1
}

# Lê o arquivo de configuração
$Config = Get-Content $ConfigFile | ConvertFrom-StringData

# Separa usuários e grupos
$Users = $Config.Users -split ';' | ForEach-Object { $_.Trim() }
$Groups = $Config.Groups -split ';' | ForEach-Object { $_.Trim() }

# Array para armazenar resultados
$Results = @()

Write-Host "`n=== INICIANDO ADIÇÃO DE USUÁRIOS AOS GRUPOS ===" -ForegroundColor Cyan
Write-Host "Data/Hora: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')`n" -ForegroundColor Gray

# Processa cada usuário
foreach ($User in $Users) {
    Write-Host "Processando usuário: $User" -ForegroundColor Yellow

    # Verifica se o usuário existe
    try {
        $ADUser = Get-ADUser -Identity $User -ErrorAction Stop
        $UserExists = $true
        $UserDN = $ADUser.DistinguishedName
    }
    catch {
        $UserExists = $false
        Write-Host "  [ERRO] Usuário não encontrado no AD" -ForegroundColor Red
    }

    # Processa cada grupo para o usuário atual
    foreach ($Group in $Groups) {
        $Result = [PSCustomObject]@{
            Usuario = $User
            Grupo = $Group
            Status = ""
            Mensagem = ""
            DataHora = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
        }

        if (-not $UserExists) {
            $Result.Status = "FALHA"
            $Result.Mensagem = "Usuário não existe no Active Directory"
            $Results += $Result
            continue
        }

        # Verifica se o grupo existe
        try {
            $ADGroup = Get-ADGroup -Identity $Group -ErrorAction Stop

            # Verifica se o usuário já é membro
            $IsMember = Get-ADGroupMember -Identity $Group | Where-Object { $_.DistinguishedName -eq $UserDN }

            if ($IsMember) {
                $Result.Status = "JÁ EXISTE"
                $Result.Mensagem = "Usuário já é membro do grupo"
                Write-Host "  [$Group] Usuário já é membro" -ForegroundColor DarkYellow
            }
            else {
                # Adiciona o usuário ao grupo
                Add-ADGroupMember -Identity $Group -Members $User -ErrorAction Stop
                $Result.Status = "SUCESSO"
                $Result.Mensagem = "Usuário adicionado com sucesso"
                Write-Host "  [$Group] Adicionado com sucesso" -ForegroundColor Green
            }
        }
        catch {
            $Result.Status = "FALHA"
            $Result.Mensagem = $_.Exception.Message
            Write-Host "  [$Group] ERRO: $($_.Exception.Message)" -ForegroundColor Red
        }

        $Results += $Result
    }

    Write-Host ""
}

# Gera relatório CSV
$ReportFile = "C:\Scripts\PS1\Relatorio_Adicao_Grupos_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" #Ajuste local de Saida
$Results | Export-Csv -Path $ReportFile -NoTypeInformation -Encoding UTF8

# Exibe resumo
Write-Host "=== RESUMO DA OPERAÇÃO ===" -ForegroundColor Cyan
Write-Host "Total de operações: $($Results.Count)" -ForegroundColor White
Write-Host "Sucesso: $(($Results | Where-Object {$_.Status -eq 'SUCESSO'}).Count)" -ForegroundColor Green
Write-Host "Já existente: $(($Results | Where-Object {$_.Status -eq 'JÁ EXISTE'}).Count)" -ForegroundColor DarkYellow
Write-Host "Falhas: $(($Results | Where-Object {$_.Status -eq 'FALHA'}).Count)" -ForegroundColor Red
Write-Host "`nRelatório gerado: $ReportFile" -ForegroundColor Cyan
