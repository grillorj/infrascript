# Coleta informações do OS
$os = Get-CimInstance Win32_OperatingSystem
$caption    = $os.Caption
$version    = $os.Version
$arch       = $os.OSArchitecture

$supportPhase  = "Desconhecido"
$mainEnd       = "Desconhecido"
$extendedEnd   = "Desconhecido"

# SO
if ($caption -like "*Microsoft Windows 10*") {
    $mainEnd     = "2025-10-14"
    $extendedEnd = "2025-10-14"
}
if ($caption -like "*Microsoft Windows 11*") {
    $mainEnd     = "2027-10-12"
    $extendedEnd = "2027-10-12"
}
if ($caption -like "*Windows Server 2008*") {
    $mainEnd     = "2015-01-14"
    $extendedEnd = "2020-01-14"
}
if ($caption -like "*Windows Server 2012*") {
    $mainEnd     = "2018-10-09"
    $extendedEnd = "2025-10-15"
}
if ($caption -like "*Windows Server 2012 R2*") {
    $mainEnd     = "2018-10-09"
    $extendedEnd = "2023-10-10"
}
if ($caption -like "*Windows Server 2016*") {
    $mainEnd     = "2022-01-11"
    $extendedEnd = "2027-01-12"
}
elseif ($caption -like "*Windows Server 2019*") {
    $mainEnd     = "2024-01-09"
    $extendedEnd = "2029-01-09"
}
if ($caption -like "*Windows Server 2022*") {
    $mainEnd     = "2026-10-13"
    $extendedEnd = "2031-10-17"
}
if ($caption -like "*Windows Server 2025*") {
    $mainEnd     = "2026-10-13"
    $extendedEnd = "2031-10-14"
}

# Definir fase com base na data atual
$today = (Get-Date).ToString("yyyy-MM-dd")

if ($mainEnd -ne "Desconhecido" -and $today -lt $mainEnd) {
    $supportPhase = "Com Suporte"
}
if ($extendedEnd -ne "Desconhecido" -and $today -le $extendedEnd) {
    $supportPhase = "Suporte Extendido"
}
if ($extendedEnd -ne "Desconhecido" -and $today -gt $extendedEnd) {
    $supportPhase = "Sem Suporte"
}

# Saída delimitada por pipe (|)
# OS_Name | OS_Version | OS_Arch | Support_Phase | Mainstream_End_Date | Extended_End_Date
Write-Output "$caption|$version|$arch|$supportPhase|$mainEnd|$extendedEnd"
