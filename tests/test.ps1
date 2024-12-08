#$repoRoot = $Env:BUILD_REPOSITORY_NAME
#Set-Location $repoRoot
#$sourceDir = $Env:BUILD_SOURCESDIRECTORY
$sourceDir = "TOTEST" 

. $PSScriptRoot/CheckHelper.ps1

# Detect if migration or publish: only one tag = migration
$gitTagList = Get-GitTagList

$isMigration = $gitTagList.Length -eq 1 -and $gitTagList.Contains("migration")
if ($isMigration) { Write-Host  "##[command]Migration" } else { Write-Host "##[command]Publish" }
 
# All files or only one given ?
#$inputApiName = $($ENV:API_PLATFORM_API).trim()
$inputApiName = "*"
Write-Host "##[command]Input api name to publish: '$($inputApiName)'"
$checkWithGitTag = $inputApiName -eq '*' 
 
# Check API to publish and to check
if ($checkWithGitTag) {
    $result = Get-ComponentsFromGitTags -GitTagList $gitTagList
}
else {
    $result = Get-ComponentsFromApiFileName -ApiFilename $inputApiName
}

# API to publish
$apiFilesToPublish = $result.ApiFilesToPublish

# Add modified API files to check based on Git tag
$apiFilesToPublish += Get-ModifiedApiFiles -GitTagList $gitTagList -ApiFileToCheck $result.ApiFilesToCheck

# Convert API files to pubish
$apisToPublish = ConvertTo-ApisToPublish -FileList $apiFilesToPublish -SourceDir $sourceDir

# Convert Domain files to pubish
$domainsToPublish = ConvertTo-DomainsToPublish -FileList $result.DomainFilesToPublish

# Set output variables
$apisToPublishJson = (ConvertTo-Json $apisToPublish -Depth 100 -Compress).Trim()
$domainsToPublishJson = (ConvertTo-Json $domainsToPublish -Depth 100 -Compress).Trim()
Write-Host "##vso[task.setvariable variable=API_PLATFORM_API_TO_PUBLISH;isOutput=true]$($apisToPublishJson)"
Write-Host "##vso[task.setvariable variable=API_PLATFORM_DOMAIN_TO_PUBLISH;isOutput=true]$($domainsToPublishJson)"
Write-Host "##vso[task.setvariable variable=API_PLATFORM_MIGRATION;isOutput=true]$($isMigration)"

# Log
if ($apisToPublish.Length -gt 0) {
    Write-Host "##[command]API to publish : $($apisToPublishJson)"
    Invoke-GitTag -FileList $apisToPublish
}
else {
    Write-Host "##[command]No API to publish."
}

if ($domainsToPublish.Length -gt 0) {
    Write-Host "##[command]Domain to publish : $($domainsToPublishJson)"
    Invoke-GitTag -FileList $domainsToPublish
}
else {
    Write-Host "##[command]No Domain to publish."
}

if ($apiFilesToPublish.Length -gt 0 -or $domainsToPublish.Length -gt 0) {
    Write-Host "##[command]Push All tags"
    $res = git push origin --tag
    Write-Host "##[command]$($res)"
}
