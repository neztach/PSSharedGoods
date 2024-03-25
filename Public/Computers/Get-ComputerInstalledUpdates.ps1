﻿function Get-ComputerInstalledUpdates {
    [CmdletBinding()]
    param(
        [string[]] $ComputerName = $Env:COMPUTERNAME,
        [ValidateSet(
            'Antivirus',
            'Cumulative Update',
            'Windows Update',
            'Servicing Stack Update',
            'Other'
        )][string[]] $IncludeType,
        [ValidateSet(
            'Antivirus',
            'Cumulative Update',
            'Windows Update',
            'Servicing Stack Update',
            'Other'
        )][string[]] $ExcludeType,
        [string] $SearchKB
    )
    # https://learn.microsoft.com/en-us/windows/win32/api/wuapi/
    <#
    These properties are part of the `IUpdateHistoryEntry` interface in the Windows Update Agent API. Here's what they mean:

    - `Operation`: This property indicates the type of operation that was performed. It's an integer that corresponds to one of the following values:
      - 1: Installation
      - 2: Uninstallation
      - 3: Other

    - `ResultCode`: This property indicates the result of the operation. It's an integer that corresponds to one of the following values:
      - 1: In Progress
      - 2: Succeeded
      - 3: Succeeded With Errors
      - 4: Failed
      - 5: Aborted

    - `HResult`: This property contains the HRESULT of the operation. An HRESULT is a type of error code used in Windows programming. A value of 0 typically means the operation was successful.

    - `UnmappedResultCode`: This property contains the result code of the operation as returned by the update installer. The exact meaning of this value can vary depending on the installer that was used.

    - `ServerSelection`: This property indicates the type of server that was used for the operation. It's an integer that corresponds to one of the following values:
      - 0: Default
      - 1: Managed server
      - 2: Self-update server
      - 3: Other

    - `ServiceID`: This property contains the ID of the service that performed the operation. For updates installed through Windows Update, this will typically be the ID of the Windows Update service.

    Please note that these are general descriptions and the exact meaning of these properties can depend on the specific update and the context in which it was installed. For more detailed information, you may need to refer to the documentation for the Windows Update Agent API.
    #>
    $Properties = @(
        'ComputerName', 'InstalledOn', 'KB', 'Categories', 'Type', 'Version', 'Title', 'ClientApplicationID', 'InstalledFrom',
        'Description', 'Operation', 'Status', 'SupportUrl', 'UpdateID', 'RevisionNumber',
        'UnmappedResultCode', 'HResult', 'ServiceID', 'UninstallationSteps', 'UninstallationNotes'
    )
    $ScriptBlock = {
        <#
        $Session = New-Object -ComObject Microsoft.Update.Session
        $Searcher = $Session.CreateUpdateSearcher()
        $historyCount = $Searcher.GetTotalHistoryCount()
        $QueryHistory = $Searcher.QueryHistory(0, $historyCount)
        $QueryHistory
        #>
        $Session = New-Object -ComObject Microsoft.Update.Session
        $Searcher = $Session.CreateUpdateSearcher()
        $historyCount = $Searcher.GetTotalHistoryCount()
        $kbRegex = '(KB\d+)'
        $versionRegex = 'Version (\d+\.\d+\.\d+\.\d+)'

        $QueryHistory = $Searcher.QueryHistory(0, $historyCount)
        $QueryHistory | Where-Object date -GT (Get-Date "1/1/2000") | ForEach-Object {
            $KbMatch = Select-String $kbRegex -InputObject $_.Title
            $Kb = if ($kbMatch) { $kbMatch.matches.groups[0].value } else { $null }

            $VersionMatch = Select-String $VersionRegex -InputObject $_.Title
            $Version = if ($VersionMatch) { $VersionMatch.matches.groups[1].value } else { $null }

            $Categories = $_.Categories | ForEach-Object { $_.Name }
            # $uninstallationSteps = $_.UninstallationSteps | ForEach-Object { $_ }

            if ($_.Title -like "*Security Intelligence Update*" -or $_.Title -like "*Antivirus*" -or $_.Title -like "*Malicious Software*") {
                $Type = "Antivirus"
            } elseif ($_.Title -like "*Cumulative Update*") {
                $Type = "Cumulative Update"
            } elseif ($_.Title -like "*Update for Windows*" -or $_.Title -like "*Security Update*" -or $_.Title -like "*Update for Microsoft*" -or $_.Title -like "*Update for Internet Explorer*") {
                $Type = "Windows Update"
            } elseif ($_.Title -like "*Servicing Stack Update*") {
                $Type = "Servicing Stack Update"
            } else {
                $Type = "Other"
            }

            [PSCustomObject]@{
                "ComputerName"        = $Env:COMPUTERNAME
                "InstalledOn"         = $_.Date
                "KB"                  = $Kb
                "Categories"          = $Categories #-join ', '
                "Type"                = $Type
                "Version"             = $Version
                "ClientApplicationID" = $_.ClientApplicationID
                "InstalledFrom"       = switch ($_.ServerSelection) { 0 { "Default" }; 1 { "Managed Server" }; 2 { "Windows Update" }; 3 { "Others" } }
                "Title"               = $_.Title
                "Description"         = $_.Description
                "Operation"           = switch ($_.operation) { 1 { "Installation" }; 2 { "Uninstallation" }; 3 { "Other" } }
                "Status"              = switch ($_.resultcode) { 1 { "In Progress" }; 2 { "Succeeded" }; 3 { "Succeeded With Errors" }; 4 { "Failed" }; 5 { "Aborted" } }
                "SupportUrl"          = $_.SupportUrl
                "UpdateID"            = $_.UpdateIdentity.UpdateID
                "RevisionNumber"      = $_.UpdateIdentity.RevisionNumber
                "UnmappedResultCode"  = $_.UnmappedResultCode
                "HResult"             = $_.HResult
                "ServiceID"           = $_.ServiceID
                "UninstallationSteps" = $_.UninstallationSteps.Name
                "UninstallationNotes" = $_.UninstallationNotes
            }
        }
    }

    [Array] $ComputersSplit = Get-ComputerSplit -ComputerName $ComputerName

    $Computers = $ComputersSplit[1]
    $Data = if ($Computers.Count -gt 0) {
        foreach ($Computer in $Computers) {
            try {
                Invoke-Command -ComputerName $Computer -ScriptBlock $ScriptBlock -ErrorAction Stop | Select-Object -Property $Properties
            } catch {
                Write-Warning -Message "Get-ComputerInstalledUpdates - No data for computer $Computer. Failed with error: $($_.Exception.Message)"
            }
        }
    } else {
        try {
            Invoke-Command -ScriptBlock $ScriptBlock -ErrorAction Stop
        } catch {
            Write-Warning -Message "Get-ComputerInstalledUpdates - No data for computer $($Env:COMPUTERNAME). Failed with error: $($_.Exception.Message)"
        }
    }
    if ($SearchKB) {
        foreach ($D in $Data) {
            if ($D.KB -like "*$SearchKB*") {
                $D
            }
        }
    } else {
        foreach ($Update in $Data) {
            if ($IncludeType -and $IncludeType -notcontains $Update.Type) {
                continue
            }
            if ($ExcludeType -and $ExcludeType -contains $Update.Type) {
                continue
            }
            $Update
        }
    }
}