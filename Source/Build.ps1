$currentDirectoryPath = (Get-Item '.\').FullName;
$artifactsDirectoryPath = [System.IO.Path]::Combine($currentDirectoryPath, 'Artifacts');
$projectFilePaths = @([System.IO.Path]::Combine($currentDirectoryPath, 'Source\Serilog.Exceptions\Serilog.Exceptions.xproj'));
$testProjectDirectoryPaths = @([System.IO.Path]::Combine($currentDirectoryPath, 'Source\Serilog.Exceptions.Test'));

$revision = @{ $true = $env:APPVEYOR_BUILD_NUMBER; $false = 1 }[$env:APPVEYOR_BUILD_NUMBER -ne $NULL];
$revision = "{0:D4}" -f [convert]::ToInt32($revision, 10);

<#
.SYNOPSIS
    You can add this to you build script to ensure that psbuild is available before calling
    Invoke-MSBuild. If psbuild is not available locally it will be downloaded automatically.
#>
function EnsurePsbuildInstalled{
    [cmdletbinding()]
    param(
        [string]$psbuildInstallUri = 'https://raw.githubusercontent.com/ligershark/psbuild/master/src/GetPSBuild.ps1'
    )
    process{
        if(-not (Get-Command "Invoke-MsBuild" -errorAction SilentlyContinue)){
            'Installing psbuild from [{0}]' -f $psbuildInstallUri | Write-Verbose
            (new-object Net.WebClient).DownloadString($psbuildInstallUri) | iex
        }
        else{
            'psbuild already loaded, skipping download' | Write-Verbose
        }

        # make sure it's loaded and throw if not
        if(-not (Get-Command "Invoke-MsBuild" -errorAction SilentlyContinue)){
            throw ('Unable to install/load psbuild from [{0}]' -f $psbuildInstallUri)
        }
    }
}

# Taken from psake https://github.com/psake/psake

<#
.SYNOPSIS
  This is a helper function that runs a scriptblock and checks the PS variable $lastexitcode
  to see if an error occcured. If an error is detected then an exception is thrown.
  This function allows you to run command-line programs without having to
  explicitly check the $lastexitcode variable.
.EXAMPLE
  exec { svn info $repository_trunk } "Error executing SVN. Please verify SVN command-line client is installed"
#>
function Exec
{
    [CmdletBinding()]
    param(
        [Parameter(Position=0,Mandatory=1)][scriptblock]$cmd,
        [Parameter(Position=1,Mandatory=0)][string]$errorMessage = ($msgs.error_bad_command -f $cmd)
    )
    & $cmd
    if ($lastexitcode -ne 0) {
        throw ("Exec: " + $errorMessage)
    }
}

if (Test-Path $artifactsDirectoryPath)
{
    Remove-Item $artifactsDirectoryPath -Force -Recurse;
}

New-Item -ItemType Directory -Force -Path $artifactsDirectoryPath;

EnsurePsbuildInstalled;

Exec { & dotnet restore };

Invoke-MSBuild $projectFilePaths -configuration Release;

foreach ($testProjectDirectoryPath in $testProjectDirectoryPaths)
{
    $projectDirectoryName = [System.IO.Path]::GetFileName($testProjectDirectoryPath);
    $outputFilePath = [System.IO.Path]::Combine($artifactsDirectoryPath, "$projectDirectoryName.xml");

    Exec { & dotnet test $testProjectDirectoryPath -c Release -xml $outputFilePath };

    if ($env:APPVEYOR_JOB_ID)
    {
        $wc = New-Object 'System.Net.WebClient';
        $wc.UploadFile(
            "https://ci.appveyor.com/api/testresults/xunit/$($env:APPVEYOR_JOB_ID)",
            $outputFilePath)
    }
}

foreach ($projectFilePath in $projectFilePaths)
{
    $projectDirectoryPath = [System.IO.Path]::GetDirectoryName($projectFilePath);
    Exec { & dotnet pack $projectDirectoryPath -c Release -o $artifactsDirectoryPath };
    Exec { & dotnet pack $projectDirectoryPath -c Release -o $artifactsDirectoryPath --version-suffix="build$revision" };
}