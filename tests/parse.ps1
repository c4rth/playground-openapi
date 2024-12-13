# Path to the OpenAPI YAML file
$yamlFilePath = "/Users/carth/Development/github.c4rth/playground-openapi/ecommerce/ecommerce-openapi-v1.0.0.yaml"

# Function to parse YAML
function Parse-Yaml($Lines) {
    $result = @{}

    $stack = @()
    $currentObject = $result
    $currentKey = ""
    $currentIndent = -1

    foreach ($line in $Lines) {
        if ($line -match "^(\s*)([^:]+):(?:\s*(.*))?$") {
            $indent = $matches[1].Length
            $key = $matches[2]
            $value = $matches[3]

            # Adjust current context based on indentation
            while ($indent -lt $currentIndent) {
                $pop = $stack[-1]
                $stack = $stack[0..($stack.Length - 2)]
                $currentObject = $pop.Object
                $currentKey = $pop.Key
                $currentIndent -= 2
            }

            if ($indent -gt $currentIndent) {
                if (-not $currentObject[$currentKey]) {
                    $currentObject[$currentKey] = @{}
                }
                $stack += @([pscustomobject]@{ Object = $currentObject; Key = $currentKey })
                $currentObject = $currentObject[$currentKey]
                $currentIndent = $indent
            }

            $currentKey = $key
            if ($value -ne "") {
                # Ensure values are properly initialized
                if (-not ($currentObject -is [hashtable])) {
                    $currentObject = @{}
                }
                $currentObject[$currentKey] = $value
            } else {
                if (-not ($currentObject -is [hashtable])) {
                    $currentObject = @{}
                }
                $currentObject[$currentKey] = @{}
            }
        } elseif ($line -match "^- (.+)") {
            if (-not ($currentObject[$currentKey] -is [array])) {
                $currentObject[$currentKey] = @()
            }
            $currentObject[$currentKey] += $matches[1]
        }
    }

    # Return the result
    return $result[""]
}

$lines = [System.IO.File]::ReadAllLines($yamlFilePath)
# Parse the YAML content
try {
 
$parsedYaml = Parse-Yaml -Lines $lines
Write-Host $parsedYaml

#Write-Host $parsedYaml[""]
Write-Host $parsedYaml["info"]
Write-Host $parsedYaml["info"]["title"]
#Write-Host $parsedYaml[""]["info"]
#Write-Host $parsedYaml[""]["info"]["title"]

# Display parsed content for testing
#Write-Host "Parsed YAML Structure:"
#$parsedYaml.GetEnumerator() | ForEach-Object { Write-Output $_ }   
}
catch {
    Write-Host "Houps"
    <#Do this if a terminating exception happens#>
}
