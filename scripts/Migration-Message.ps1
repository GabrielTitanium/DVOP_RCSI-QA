# Define paths and webhook
$logFile = "C:\Build\DataMigrationLog.txt"
$webhookUrl = "https://titaniumsolutionsltd.webhook.office.com/webhookb2/5c832395-1c41-4de3-be95-5f51dedafba0@26219bd8-7fd9-4860-bf47-ed0ce0a65a2f/IncomingWebhook/f6c1d5277de849fab4e38ce2104c84da/3e949257-b28a-43fc-a05c-9d443eea3752/V29PcTbu4xvfH4xazgJk1AvIetYqXwEP34EPMSIBcOcwk1"
$buildNumber = $env:BUILD_BUILDNUMBER
$branchName = 'Salud Services Trunk'
$serverName = 'eu-rcsi-qa-int.titanium.solutions'
$server = 'sql2.tth.ds\test'
$dbName = "RCSI_QA"

$pipelineRunUrl = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_build/results?buildId=$($env:BUILD_BUILDID)"

# Read log
if (!(Test-Path $logFile)) {
    Write-Host "Log file not found: $logFile"
    exit 1
}

$logLines = Get-Content -Path $logFile

# Try to locate failure markers
$failurePattern = "Migration process failed with exit code: 1"
$altFailurePattern = "Migration"  # fallback for broader matching

$failureLine = $logLines | Where-Object { $_ -match $failurePattern }

if (-not $failureLine) {
    $failureLine = $logLines | Where-Object { $_ -match $altFailurePattern }
}

if ($failureLine) {
    $failureIndex = [array]::IndexOf($logLines, $failureLine[0])
} else {
    Write-Host "No failure pattern found in log file. Sending last few lines instead."
    $failureIndex = $logLines.Count - 51
    if ($failureIndex -lt 0) { $failureIndex = 0 }
}

# Extract tail of log
$logContent = $logLines[($failureIndex + 1)..($logLines.Count - 1)] -join "`n"

# If too long, trim to last 40 lines
$maxLines = 40
if (($logContent.Split("`n").Count) -gt $maxLines) {
    $logContent = ($logContent -split "`n")[-$maxLines..-1] -join "`n"
    $logContent = "[Showing last $maxLines lines of log...]`n`n" + $logContent
}

# Escape double quotes
$escapedContent = $logContent -replace '"', '\"'

# Prepare variable summary section
$variableSummary = @"
**Migration Details**
- Server Name: $serverName
- Build Number: $buildNumber
- Branch Name: $branchName
- Server: $server
- Target Database: $dbName
"@

# Build Teams MessageCard
$message = @"
{
  "@type": "MessageCard",
  "@context": "https://schema.org/extensions",
  "summary": "Data Migration Failed",
  "themeColor": "FF0000",
  "title": "Data Migration Failed",
  "text": "The data migration process has failed. Review the details and log extract below.",
  "sections": [
    {
      "activityTitle": "Migration Information",
      "text": "$variableSummary",
      "markdown": true
    },
    {
      "activityTitle": "Failure Log Extract",
      "text": "```\n$escapedContent\n```",
      "markdown": true
    },
    {
      "@type": "OpenUri",
      "name": "Open Failed Pipeline Run",
      "targets": [
        { "os": "default", "uri": "$pipelineRunUrl" }
      ]
    }
  ]
}
"@

# Send message to Teams
try {
    Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $message -ContentType 'application/json'
    Write-Host "Log content and migration details sent to Microsoft Teams."
}
catch {
    Write-Host "Failed to send Teams notification: $_"
    exit 1
}
