# =========================
# GENERIC ENVIRONMENT MANAGER REPL
# =========================

# --- Utility Functions ---
function Normalize-Input { param ($value) return $value.Trim() }

function Get-EnvSnapshot {
    return [System.Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
}

function Load-Environment { param ($scope)
    $envTable = Get-EnvSnapshot
    [System.Environment]::GetEnvironmentVariables($scope).GetEnumerator() |
        ForEach-Object { $envTable[$_.Key] = $_.Value }
    return $envTable
}

function Save-Environment { param ($envTable, $scope)
    foreach ($key in $envTable.Keys) {
        [System.Environment]::SetEnvironmentVariable($key, $envTable[$key], $scope)
    }
}

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-SessionPath {
    param($envTable)
    # Update current session PATH if PATH variable is changed
    if ($envTable.ContainsKey("PATH")) {
        $env:Path = $envTable["PATH"]
    }
}

# --- Admin Check ---
if (-not (Is-Admin)) { Write-Error "Run as Administrator."; exit 1 }

# --- Initial State ---
$Scope = "Machine"  # Can be "User" if you want user-scoped changes
$RealEnv = Load-Environment $Scope
$WorkingEnv = $RealEnv
$DemoMode = $false

Write-Host "`nEnvironment Manager REPL"
Write-Host "Commands: add | delete | search | demo | exit`n"

# --- REPL Loop ---
while ($true) {
    $command = Normalize-Input (Read-Host ">")

    switch ($command.ToLower()) {

        "add" {
            $input = Normalize-Input (Read-Host "VAR_NAME=VALUE")
            if ($input -notmatch "=") { Write-Host "Invalid format. Use VAR_NAME=VALUE"; break }

            $name, $value = $input.Split("=", 2) | ForEach-Object { $_.Trim() }
            if ([string]::IsNullOrEmpty($name) -or [string]::IsNullOrEmpty($value)) { Write-Host "Variable name or value empty."; break }

            if ($WorkingEnv.ContainsKey($name)) {
                # Avoid duplicates in PATH-like variables
                if ($name.ToUpper() -eq "PATH") {
                    $paths = $WorkingEnv[$name].Split(";") | ForEach-Object { $_.Trim() }
                    if ($paths -contains $value) { Write-Host "Path already exists in $name" }
                    else { $WorkingEnv[$name] += ";$value"; Write-Host "Path appended to $name" }
                } else {
                    $WorkingEnv[$name] = $value
                    Write-Host "Variable $name overwritten"
                }
            } else {
                $WorkingEnv[$name] = $value
                Write-Host "Variable $name created"
            }

            if (-not $DemoMode) {
                Save-Environment $WorkingEnv $Scope
                Update-SessionPath $WorkingEnv
            }
        }

        "delete" {
            $name = Normalize-Input (Read-Host "VAR_NAME")
            if ($WorkingEnv.ContainsKey($name)) {
                $WorkingEnv.Remove($name)
                Write-Host "Variable $name removed"
                if (-not $DemoMode) {
                    [System.Environment]::SetEnvironmentVariable($name,$null,$Scope)
                    Update-SessionPath $WorkingEnv
                }
            } else { Write-Host "Variable not found" }
        }

        "search" {
            Write-Host "`n--- Environment Variables ---"
            foreach ($key in $WorkingEnv.Keys | Sort-Object) {
                Write-Host "$key = $($WorkingEnv[$key])"
            }
            Write-Host ""
        }

        "demo" {
            if (-not $DemoMode) { 
                $WorkingEnv = Load-Environment $Scope
                $DemoMode = $true
                Write-Host "Demo mode ON (changes NOT persistent)"
            } else {
                $WorkingEnv = $RealEnv
                $DemoMode = $false
                Update-SessionPath $WorkingEnv
                Write-Host "Demo mode OFF (reverted)"
            }
        }

        "exit" { Write-Host "Exiting..."; break }

        default { Write-Host "Unknown command. Use: add | delete | search | demo | exit" }
    }
}
