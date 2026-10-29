function Clean([object]$v) {
    if ($null -eq $v) { return 'N/A' }
    $s = ([string]$v).Replace('|', '/').Replace("`r", '').Replace("`n", ' ').Trim()
    if ($s -eq '') { return 'N/A' }
    return $s
}

function Find-Azcmagent {
    $roots = @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($root in $roots) {
        $p = [System.IO.Path]::Combine($root, 'AzureConnectedMachineAgent\azcmagent.exe')
        if ([System.IO.File]::Exists($p)) { return $p }
    }
    return $null
}

function Invoke-Azcmagent([string]$Exe, [string]$Arguments) {
    $proc = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $errTask = $null
        $outTask = $null
        try {
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
        }
        catch { $outTask = $null }
        if ($null -eq $outTask) {
            $text = $proc.StandardOutput.ReadToEnd()
            if (-not $proc.WaitForExit(20000)) { try { $proc.Kill() } catch {} ; return $null }
            if ($proc.ExitCode -ne 0) { return $null }
            return $text
        }
        if (-not $proc.WaitForExit(20000)) { try { $proc.Kill() } catch {} ; return $null }
        if (-not $outTask.Wait(5000)) { return $null }
        if ($proc.ExitCode -ne 0) { return $null }
        return $outTask.Result
    }
    catch { return $null }
    finally { if ($proc) { $proc.Close() } }
}

function Get-JsonValue($Json, [string[]]$Names) {
    if ($null -eq $Json) { return $null }
    foreach ($n in $Names) {
        foreach ($prop in $Json.PSObject.Properties) {
            if ($prop.Name -ieq $n -and $null -ne $prop.Value -and ([string]$prop.Value) -ne '') { return $prop.Value }
        }
    }
    return $null
}

function Get-TextValue([string]$Text, [string[]]$Labels) {
    if (-not $Text) { return $null }
    foreach ($line in ($Text -split "`n")) {
        $idx = $line.IndexOf(':')
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx).Trim()
        foreach ($l in $Labels) {
            if ($key -ieq $l) { return $line.Substring($idx + 1).Trim() }
        }
    }
    return $null
}

function Get-ServiceStates {
    $map = @(
        @('himds', 'himds'),
        @('arcproxy', 'ArcProxy'),
        @('extensionservice', 'ExtensionService'),
        @('gcarcservice', 'GCArcService')
    )
    $parts = New-Object System.Collections.ArrayList
    foreach ($m in $map) {
        $state = 'notfound'
        try {
            $svc = Get-Service -Name $m[1] -ErrorAction Stop
            $state = $svc.Status.ToString().ToLower()
        }
        catch {}
        $null = $parts.Add($m[0] + '=' + $state)
    }
    return ($parts -join ';')
}

function Get-Result {
    $exe = Find-Azcmagent
    if ($null -eq $exe) {
        'No|Not installed|Not installed|||||' + '|' + ''
        return
    }
    $services = Get-ServiceStates
    $json = $null
    $text = $null
    $jsonText = Invoke-Azcmagent $exe 'show -j'
    if ($jsonText) {
        try { $json = $jsonText | ConvertFrom-Json } catch { $json = $null }
    }
    if ($null -eq $json) { $text = Invoke-Azcmagent $exe 'show' }
    if ($null -eq $json -and -not $text) {
        $ver = Invoke-Azcmagent $exe 'version'
        $verText = 'N/A'
        if ($ver -match '(\d+(\.\d+)+)') { $verText = $Matches[1] }
        'Yes|' + $verText + '|Error: azcmagent show failed or timed out|N/A|N/A|N/A|N/A|N/A|' + $services
        return
    }
    $version = Get-JsonValue $json @('agentVersion', 'version')
    $status = Get-JsonValue $json @('status', 'agentStatus')
    $rname = Get-JsonValue $json @('resourceName')
    $rgroup = Get-JsonValue $json @('resourceGroup', 'resourceGroupName')
    $sub = Get-JsonValue $json @('subscriptionId')
    $tenant = Get-JsonValue $json @('tenantId')
    $beat = Get-JsonValue $json @('lastHeartbeat', 'agentLastHeartbeat')
    if ($null -eq $json) {
        $version = Get-TextValue $text @('Agent Version')
        $status = Get-TextValue $text @('Agent Status')
        $rname = Get-TextValue $text @('Resource Name')
        $rgroup = Get-TextValue $text @('Resource Group Name', 'Resource Group')
        $sub = Get-TextValue $text @('Subscription ID')
        $tenant = Get-TextValue $text @('Tenant ID')
        $beat = Get-TextValue $text @('Agent Last Heartbeat', 'Last Heartbeat')
    }
    if ($null -eq $version) {
        $ver = Invoke-Azcmagent $exe 'version'
        if ($ver -match '(\d+(\.\d+)+)') { $version = $Matches[1] }
    }
    $fields = @('Yes', (Clean $version), (Clean $status), (Clean $rname), (Clean $rgroup), (Clean $sub), (Clean $tenant), (Clean $beat), $services)
    $fields -join '|'
}

try { Get-Result }
catch { 'Error|Error: unable to query azcmagent|Error||||||' }
