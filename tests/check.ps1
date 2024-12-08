$repoRoot = $Env:BUILD_REPOSITORY_NAME
Set-Location $repoRoot
$sourceDir = $Env:BUILD_SOURCESDIRECTORY
 
# Detect if migration or publish: only one tag = migration
$gitTagList = @()
$tags = git tag --list
$gitTagList += $tags
$isMigration = $gitTagList.Length -eq 1 -and $gitTagList.Contains("migration")
if ($isMigration) {
    Write-Host "##[command]Migration"
}
else {
    Write-Host "##[command]Publish"
}
 
# All files or only one given ?
$apiName = $($ENV:API_PLATFORM_API).trim()
Write-Host "##[debug]apiNames: $($apiName)"
$checkWithGitTag = $apiName -eq '*' 
 
# Check API
$apisToPublish = @()
$domainsToPublish = @()
$apisToCheck = @()
if ($checkWithGitTag) {
    Write-Host "##[debug]Check with git tags"
    # Files to publish or to check: file is tagged with its name
    $allApiFiles = Get-ChildItem -Path "." -Exclude @("domains", "devops") | Get-ChildItem -Recurse -File -Depth 255 -Filter "*.yaml"
    foreach ($file in $allApiFiles) {
        if ($gitTagList.Contains($file.BaseName)) {
            $apisToCheck += $file
        }
        else {
            $apisToPublish += $file
        }
    }
    # Check if domains modified: modified between HEAD and tag
    $allDomainFiles = Get-ChildItem -Path "./domains/" -Recurse -File -Depth 255 -Filter "*.yaml"
    foreach ($domain in $allDomainFiles) {
        $isModified = $True
        if ($gitTagList.Contains($domain.BaseName)) {
            $res = git diff --exit-code --name-only $domain.BaseName -- $domain.FullName
            $isModified = $res.length -gt 0
        }
        if ($isModified) {
            Write-Host "##[debug]Domain modified: $($domain.BaseName)"
            $domainsToPublish += $domain
        }
    }
    # Check which API uses the modified domains
    $updatedFileToCheck = @()
    foreach ($file in $apisToCheck) {
        $content = Get-Content $file.FullName
        foreach ($domain in $domainToCheck) {
            if ($content -match "\`$ref: '?\.\./domains/$($domain.BaseName).yaml#") {
                if ($apisToPublish.Contains($file)) {
                    Write-Host "##[debug]$($file.BaseName) contains ref to $($domain.BaseName) but already to publish -> skipped"
                } else {
                    $apisToPublish += $file
                    Write-Host "##[debug]$($file.BaseName) contains ref to $($domain.BaseName) -> to publish"
                }
            }
            else {
                $updatedFileToCheck += $file
                Write-Host "##[debug]$($file.BaseName) doesn't contain ref to $($domain.BaseName) -> to check"
            }
        }
    }
    $apisToCheck = $updatedFileToCheck
}
else {
    Write-Host "##[debug]Check with API pathname"
    if ($apiName.StartsWith("/domains/") -or $apiName.StartsWith("domains/") -or $apiName.StartsWith("/devops/") -or $apiName.StartsWith("devops/")) {
        Write-Host "##vso[task.logissue type=error]Publish domains or devops files is not allowed."
        exit 1
    }
    $apiPath = if ($apiName.StartsWith("/")) { ".$($apiName)" } else { "./$($apiName)" }
    Write-Host "##[command]Check if exists: $($apiPath)"
    if (Test-Path -Path $apiPath -PathType Leaf) {
        $file = Get-ChildItem -Path $apiPath
        $apisToPublish += $file
    }
    else {
        Write-Host "##[warning]NOT FOUND: $($apiName)"
    }
}
 
# Check if files modified between HEAD and tags
foreach ($file in $apisToCheck) {
    Write-Host "##[command]Check" $file.BaseName
    $isModified = $True
    if ($gitTagList.Contains($file.BaseName)) {
        $res = git diff --exit-code --name-only $file.BaseName -- $file.FullName
        $isModified = $res.length -gt 0
    }
    if ($isModified) {
        Write-Host "##[debug]File modified: $($file.BaseName)"
        $apisToPublish += $file
    }
    else {
        Write-Host "##[debug]File NOT modified: $($file.BaseName) -> SKIPPED"
    }
}
 
# Set variable of files to pubish
$apiToPublish = @()
foreach ($file in $apisToPublish) {
    $baseName = $file.BaseName
    if ($baseName -match '^(.+?)-v(\d+\.\d+\.\d+)(?:-([\w\-]+))?$') {
        $apiName = $matches[1]
        $version = $matches[2]
        $apiToPublish += @{
            FullName = "." + $file.FullName.Replace($sourceDir, "")
            BaseName = $file.BaseName
            ApiName  = $apiName
            Version  = $version
            Snapshot = if ($matches[3]) { $True } else { $False }
        }
    }
    else {
        Write-Host "##[warning]Cannot extract name and version from $($file.BaseName)"
    }
}
 
$apiToPublishJson = (ConvertTo-Json $apiToPublish -Depth 100 -Compress).Trim()
Write-Host "##vso[task.setvariable variable=API_PLATFORM_API_TO_PUBLISH;isOutput=true]$apiToPublishJson"
Write-Host "##vso[task.setvariable variable=API_PLATFORM_MIGRATION;isOutput=true]$isMigration"
 
if ($apiToPublish.Length -gt 0) {
    Write-Host "##[command]Files to publish:"
    Write-Host "##[command]$($apiToPublishJson)"
    <#
    foreach ($file in $apiToPublish) {
        Write-Host "##[command]$($file.FullName)"
        $res = git tag --force $file.BaseName
        Write-Host "##[command]Tag" $file.BaseName " -> " $res
        $res = git push --force origin $file.BaseName
        Write-Host "Push tag" $res
    }
    #>
}
else {
    Write-Host "##vso[task.logissue type=warning]No API to publish."
}
