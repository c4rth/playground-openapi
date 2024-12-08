# Get Git Tag list
function Get-GitTagList {
    Write-Host "##[command]Get Git tag list"
    $gitTagList = @()
    $tags = git tag --list
    if (-not $tags) {
        $tags = "migration"
    }
    $gitTagList += $tags
    $temp = ConvertTo-Json $gitTagList
    Write-Host "##[command]$($temp)"
    return $gitTagList
}

# Files to publish or to check: file is tagged with its name
function Get-ApiFilesToTreat($GitTagList) {
    Write-Host "##[command]Get API files to publish or to check"
    $apiFilesToPublish = @()
    $apiFilesToCheck = @()
    $allApiFiles = Get-ChildItem -Path "." -Exclude @("domains", "devops") | Get-ChildItem -Recurse -File -Depth 255 -Include "*.yaml"
    foreach ($file in $allApiFiles) {
        if ($GitTagList.Contains($file.BaseName)) {
            Write-Host "##[command]    API tag '$($file.BaseName)' found -> to check"
            $apiFilesToCheck += $file
        }
        else {
            Write-Host "##[command]    API tag '$($file.BaseName)' not found -> to publish"
            $apiFilesToPublish += $file
        }
    }
    return @{
        ApiFilesToPublish = $apiFilesToPublish
        ApiFilesToCheck   = $apiFilesToCheck
    }
}

# Check if domains modified: modified between HEAD and tag
function Get-DomainFilesToPublish($GitTagList) {
    Write-Host "##[command]Get Domain files to publish"
    $domainFilesToPublish = @()
    if (Test-Path -Path "./domains/") {
        $allDomainFiles = Get-ChildItem -Path "./domains/" -Recurse -File -Depth 255 -Filter "*.yaml"
        foreach ($domain in $allDomainFiles) {
            $isModified = $True
            if ($GitTagList.Contains($domain.BaseName)) {
                $res = git diff --exit-code --name-only $domain.BaseName -- $domain.FullName
                $isModified = $res.length -gt 0
            }
            if ($isModified) {
                Write-Host "##[command]    Domain '$($domain.BaseName)' modified or tag not found -> to publish"
                $domainFilesToPublish += $domain
            }
            else {
                Write-Host "##[command]    Domain '$($domain.BaseName)' not modified -> skipped"
            }
        }
    }
    else {
        Write-Host "##[command]    No Domain files in repository"
    }
    return $domainFilesToPublish
}


# Check which APIfiles uses the modified domains
function Get-ApiFilesUsingDomainFiles($ApiFilesToPublish, $ApiFilesToCheck, $DomainFilesToCheck) {
    Write-Host "##[command]Get API files using local Domain files"
    $updatedFilesToPublish = $ApiFilesToPublish
    $updatedFilesToCheck = @()
    foreach ($file in $ApiFilesToCheck) {
        $content = Get-Content $file.FullName
        foreach ($domain in $DomainFilesToCheck) {
            if ($content -match "\`$ref: '?\.\./domains/$($domain.BaseName).yaml#") {
                if ($updatedFilesToPublish.Contains($file)) {
                    Write-Host "##[command]    $($file.BaseName) contains ref to $($domain.BaseName) but already to publish -> skipped"
                }
                else {
                    $updatedFilesToPublish += $file
                    Write-Host "##[command]    $($file.BaseName) contains ref to $($domain.BaseName) -> to publish"
                }
            }
            else {
                if ($updatedFilesToCheck.Contains($file)) {
                    Write-Host "##[command]    $($file.BaseName) doesn't contain ref to $($domain.BaseName) but already to check -> skipped"
                }
                else {
                    $updatedFilesToCheck += $file
                    Write-Host "##[command]    $($file.BaseName) doesn't contain ref to $($domain.BaseName) -> to check"
                }
            }
        }
    }        
    return @{
        ApiFilesToPublish = $updatedFilesToPublish
        ApiFilesToCheck   = $updatedFilesToCheck
    }
}

# Get apis to publish, to check and domains tpopublish
function Get-ComponentsFromGitTags($GitTagList) {
    Write-Host "##[command]Get APIs and Domains using Git tags"

    # Files to publish or to check
    $result = Get-ApiFilesToTreat -GitTagList $GitTagList
    $apiFilesToPublish = $result.ApiFilesToPublish
    $apiFilesToCheck = $result.ApiFilesToCheck

    # Check domains
    $domainFilesToPublish = Get-DomainFilesToPublish -GitTagList $GitTagList

    # Check which API uses the modified domains
    if ($domainFilesToPublish.Length -gt 0) {
        $result = Get-ApiFilesUsingDomainFiles -ApiFilesToPublish $apiFilesToPublish -ApiFilesToCheck $apiFilesToCheck -DomainFilesToCheck $domainFilesToPublish
    }

    return @{
        ApiFilesToPublish    = $result.ApiFilesToPublish
        ApiFilesToCheck      = $result.ApiFilesToCheck
        DomainFilesToPublish = $domainFilesToPublish
    }
}

function Get-ComponentsFromApiFileName ($ApiFileName) {
    $apiFilesToPublish = @()
    Write-Host "##[command]Get with API pathname '$($ApiFileName)'"
    if ($ApiFileName.StartsWith("/domains/") -or $ApiFileName.StartsWith("domains/") -or $ApiFileName.StartsWith("/devops/") -or $ApiFileName.StartsWith("devops/")) {
        Write-Host "##vso[task.logissue type=error]Publish domains or devops files is not allowed."
        exit 1
    }
    $apiPath = if ($ApiFileName.StartsWith("/")) { ".$($ApiFileName)" } else { "./$($ApiFileName)" }
    Write-Host "##[command]    Check if exists: $($apiPath)"
    if (Test-Path -Path $apiPath -PathType Leaf) {
        $file = Get-ChildItem -Path $apiPath
        $apiFilesToPublish += $file
    }
    else {
        Write-Host "##[warning]    File not found '$($ApiFileName)'"
    }
    return @{
        ApiFilesToPublish    = $apiFilesToPublish
        ApiFilesToCheck      = @()
        DomainFilesToPublish = @()
    }    
}


# Check if files modified between HEAD and tags
function Get-ModifiedApiFiles($GitTagList, $ApiFileToCheck) {
    Write-Host "##[command]Check if API files are modified ($($ApiFileToCheck.Length))"
    $apiFilesModified = @()
    foreach ($file in $ApiFileToCheck) {
        Write-Host "##[command]    Check if '$($file.BaseName)' is modified"
        $isModified = $True
        if ($GitTagList.Contains($file.BaseName)) {
            $res = git diff --exit-code --name-only $file.BaseName -- $file.FullName
            $isModified = $res.length -gt 0
        }
        if ($isModified) {
            Write-Host "##[command]    File modified: $($file.BaseName)"
            $apiFilesModified += $file
        }
        else {
            Write-Host "##[command]    File NOT modified: $($file.BaseName) -> SKIPPED"
        }
    }
    return $apiFilesModified
}

# Convert API files to pubish
function ConvertTo-ApisToPublish($FileList, $SourceDir) {
    Write-Host "##[command]Convert to API to publish"
    $apisToPublish = @()
    foreach ($file in $FileList) {
        $baseName = $file.BaseName
        if ($baseName -match '^(.+?)-v(\d+\.\d+\.\d+)(?:-([\w\-]+))?$') {
            $inputApiName = $matches[1]
            $version = $matches[2]
            $apisToPublish += @{
                FullName = "." + $file.FullName.Replace($SourceDir, "")
                BaseName = $file.BaseName
                ApiName  = $inputApiName
                Version  = $version
                Snapshot = if ($matches[3]) { $True } else { $False }
            }
        }
        else {
            Write-Host "##[warning]Cannot extract name and version from $($file.BaseName)"
        }
    }
    return $apisToPublish
}

# Convert Domain files to pubish
function ConvertTo-DomainsToPublish($FileList) {
    Write-Host "##[command]Convert to Domain to publish"
    $domainsToPublish = @()
    foreach ($file in $FileList) {
        $domainsToPublish += @{
            FullName = "." + $file.FullName.Replace($sourceDir, "")
            BaseName = $file.BaseName
        }
    }
    return $domainsToPublish
}

# Add or move Git Tag 
function Invoke-GitTag($FileList) {
    foreach ($file in $FileList) {
        Write-Host "##[command]Add tag '$($file.BaseName)'"
        if ($gitTagList.Contains($file.BaseName)) {
            $res = git tag --delete $file.BaseName
            $res = git push origin :refs/tags/$($file.BaseName)
        }
        $res = git tag --force $file.BaseName
    }
}