$ErrorActionPreference = 'Stop'

$EFDefaultParameterValues = @{
    ProjectName = ''
    ContextTypeName = ''
}

#
# Use-DbContext
#

Register-TabExpansion Use-DbContext @{
    Context = { param ($tabExpansionContext) GetContextTypes $tabExpansionContext.Project $tabExpansionContext.StartupProject $tabExpansionContext.Environment }
    Project = { GetProjects }
    StartupProject = { GetProjects }
}

<#
.SYNOPSIS
    Sets the default DbContext to use.

.DESCRIPTION
    Sets the default DbContext to use.

.PARAMETER Context
    Specifies the DbContext to use.

.PARAMETER Project
    Specifies the project to use. If omitted, the default project is used.

.PARAMETER StartupProject
    Specifies the startup project to use. If omitted, the solution's startup project is used.

.PARAMETER Environment
    Specifies the environment to use. If omitted, "Development" is used.

.LINK
    about_EntityFramework
#>
function Use-DbContext {
    [CmdletBinding(PositionalBinding = $false)]
    param ([Parameter(Position = 0, Mandatory = $true)] [string] $Context, [string] $Project, [string] $StartupProject, [string] $Environment)

    $dteProject = GetProject $Project
    $dteStartupProject = GetStartupProject $StartupProject $dteProject
    if (IsDotNetProject $dteProject) {
        $contextTypes = GetContextTypes $Project $StartupProject $Environment
        $candidates = $contextTypes | ? { $_ -ilike "*$Context" }
        $exactMatch = $contextTypes | ? { $_ -eq $Context }
        if ($candidates.length -gt 1 -and $exactMatch -is "String") {
            $candidates = $exactMatch
        }

        if ($candidates.length -lt 1) {
            throw "No DbContext named '$Context' was found"
        } elseif ($candidates.length -gt 1 -and !($candidates -is "String")) {
            throw "More than one DbContext named '$Context' was found. Specify which one to use by providing its fully qualified name."
        }

        $contextTypeName=$candidates
    } else {
        $contextTypeName = InvokeOperation $dteStartupProject $Environment $dteProject GetContextType @{ name = $Context }
    }

    $EFDefaultParameterValues.ContextTypeName = $contextTypeName
    $EFDefaultParameterValues.ProjectName = $dteProject.ProjectName
}

#
# Add-Migration
#

Register-TabExpansion Add-Migration @{
    Context = { param ($tabExpansionContext) GetContextTypes $tabExpansionContext.Project $tabExpansionContext.StartupProject $tabExpansionContext.Environment }
    Project = { GetProjects }
    StartupProject = { GetProjects }
    # disables tab completion on output dir
    OutputDir = { }
}

<#
.SYNOPSIS
    Adds a new migration.

.DESCRIPTION
    Adds a new migration.

.PARAMETER Name
    Specifies the name of the migration.

.PARAMETER OutputDir
    The directory (and sub-namespace) to use. If omitted, "Migrations" is used. Relative paths are relative to project directory.

.PARAMETER Context
    Specifies the DbContext to use. If omitted, the default DbContext is used.

.PARAMETER Project
    Specifies the project to use. If omitted, the default project is used.

.PARAMETER StartupProject
    Specifies the startup project to use. If omitted, the solution's startup project is used.

.PARAMETER Environment
    Specifies the environment to use. If omitted, "Development" is used.

.LINK
    Remove-Migration
    Update-Database
    about_EntityFramework
#>
function Add-Migration {
    [CmdletBinding(PositionalBinding = $false)]
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string] $Name,
        [string] $OutputDir,
        [string] $Context,
        [string] $Project,
        [string] $StartupProject,
        [string] $Environment)

    $values = ProcessCommonParameters $StartupProject $Project $Context
    $dteStartupProject = $values.StartupProject
    $dteProject = $values.Project
    $contextTypeName = $values.ContextTypeName

    if (IsDotNetProject $dteProject) {
        $options = ProcessCommonDotnetParameters $dteProject $dteStartupProject $Environment $contextTypeName
        if($OutputDir) {
            $options += "--output-dir", (NormalizePath $OutputDir)
        }
        $files = InvokeDotNetEf $dteProject -json migrations add $Name @options
        $DTE.ItemOperations.OpenFile($files.MigrationFile) | Out-Null
    }
    else {
        $artifacts = InvokeOperation $dteStartupProject $Environment $dteProject AddMigration @{
            name = $Name
            outputDir = $OutputDir
            contextType = $contextTypeName
        }
        
        $dteProject.ProjectItems.AddFromFile($artifacts.MigrationFile) | Out-Null

        try {
            $dteProject.ProjectItems.AddFromFile($artifacts.MetadataFile) | Out-Null
        } catch {
            # in some SKUs the call to add MigrationFile will automatically add the MetadataFile because it is named ".Designer.cs"
            # this will throw a non fatal error when -OutputDir is outside the main project directory
        }

        $dteProject.ProjectItems.AddFromFile($artifacts.SnapshotFile) | Out-Null
        $DTE.ItemOperations.OpenFile($artifacts.MigrationFile) | Out-Null
        ShowConsole
    }

    Write-Output 'To undo this action, use Remove-Migration.'
}

#
# Update-Database
#

Register-TabExpansion Update-Database @{
    Migration = { param ($tabExpansionContext) GetMigrations $tabExpansionContext.Context $tabExpansionContext.Project $tabExpansionContext.StartupProject $tabExpansionContext.Environment }
    Context = { param ($tabExpansionContext) GetContextTypes $tabExpansionContext.Project $tabExpansionContext.StartupProject $tabExpansionContext.Environment }
    Project = { GetProjects }
    StartupProject = { GetProjects }
}

<#
.SYNOPSIS
    Updates the database to a specified migration.

.DESCRIPTION
    Updates the database to a specified migration.

.PARAMETER Migration
    Specifies the target migration. If '0', all migrations will be reverted. If omitted, all pending migrations will be applied.

.PARAMETER Context
    Specifies the DbContext to use. If omitted, the default DbContext is used.

.PARAMETER Project
    Specifies the project to use. If omitted, the default project is used.

.PARAMETER StartupProject
    Specifies the startup project to use. If omitted, the solution's startup project is used.

.PARAMETER Environment
    Specifies the environment to use. If omitted, "Development" is used.

.LINK
    Script-Migration
    about_EntityFramework
#>
function Update-Database {
    [CmdletBinding(PositionalBinding = $false)]
    param (
        [Parameter(Position = 0)]
        [string] $Migration,
        [string] $Context,
        [string] $Project,
        [string] $StartupProject,
        [string] $Environment)

    $values = ProcessCommonParameters $StartupProject $Project $Context
    $dteStartupProject = $values.StartupProject
    $dteProject = $values.Project
    $contextTypeName = $values.ContextTypeName

    if (IsDotNetProject $dteProject) {
        $options = ProcessCommonDotnetParameters $dteProject $dteStartupProject $Environment $contextTypeName
        InvokeDotNetEf $dteProject database update $Migration @options | Out-Null
        Write-Output "Done."
    } else {
        if (IsUwpProject $dteProject) {
            throw 'Update-Database should not be used with Universal Windows apps. Instead, call DbContext.Database.Migrate() at runtime.'
        }

        InvokeOperation $dteStartupProject $Environment $dteProject UpdateDatabase @{
            targetMigration = $Migration
            contextType = $contextTypeName
        }
    }
}

#
# Apply-Migration (Obsolete)
#

function Apply-Migration {
    # TODO: Remove before RTM
    throw 'Apply-Migration has been removed. Use Update-Database instead.'
}

#
# Script-Migration
#

Register-TabExpansion Script-Migration @{
    From = { param ($tabExpansionContext) GetMigrations $tabExpansionContext.Context $tabExpansionContext.Project $tabExpansionContext.StartupProject $tabExpansionContext.Environment }
    To = { param ($tabExpansionContext) GetMigrations $tabExpansionContext.Context $tabExpansionContext.Project $tabExpansionContext.StartupProject $tabExpansionContext.Environment }
    Context = { param ($tabExpansionContext) GetContextTypes $tabExpansionContext.Project $tabExpansionContext.StartupProject $tabExpansionContext.Environment }
    Project = { GetProjects }
    StartupProject = { GetProjects }
}

<#
.SYNOPSIS
    Generates a SQL script from migrations.

.DESCRIPTION
    Generates a SQL script from migrations.

.PARAMETER From
    Specifies the starting migration. If omitted, '0' (the initial database) is used.

.PARAMETER To
    Specifies the ending migration. If omitted, the last migration is used.

.PARAMETER Idempotent
    Generates an idempotent script that can be used on a database at any migration.

.PARAMETER Context
    Specifies the DbContext to use. If omitted, the default DbContext is used.

.PARAMETER Project
    Specifies the project to use. If omitted, the default project is used.

.PARAMETER StartupProject
    Specifies the startup project to use. If omitted, the solution's startup project is used.

.PARAMETER Environment
    Specifies the environment to use. If omitted, "Development" is used.

.LINK
    Update-Database
    about_EntityFramework
#>
function Script-Migration {
    [CmdletBinding(PositionalBinding = $false)]
    param (
        [Parameter(ParameterSetName = 'WithoutTo')]
        [Parameter(ParameterSetName = 'WithTo', Mandatory = $true)]
        [string] $From,
        [Parameter(ParameterSetName = 'WithTo', Mandatory = $true)]
        [string] $To,
        [switch] $Idempotent,
        [string] $Context,
        [string] $Project,
        [string] $StartupProject,
        [string] $Environment)

    $values = ProcessCommonParameters $StartupProject $Project $Context
    $dteStartupProject = $values.StartupProject
    $dteProject = $values.Project
    $contextTypeName = $values.ContextTypeName

    $fullPath = GetProperty $dteProject.Properties FullPath
    $intermediatePath = if (IsDotNetProject $dteProject) { "obj\Debug\" }
        else { GetProperty $dteProject.ConfigurationManager.ActiveConfiguration.Properties IntermediatePath }
    $fullIntermediatePath = Join-Path $fullPath $intermediatePath
    $fileName = [IO.Path]::GetRandomFileName()
    $fileName = [IO.Path]::ChangeExtension($fileName, '.sql')
    $scriptFile = Join-Path $fullIntermediatePath $fileName

    if (IsDotNetProject $dteProject) {
        $options = ProcessCommonDotnetParameters $dteProject $dteStartupProject $Environment $contextTypeName

        $options += "--output",$scriptFile
        if ($Idempotent) {
            $options += ,"--idempotent"
        }

        InvokeDotNetEf $dteProject migrations script $From $To @options | Out-Null

        $DTE.ItemOperations.OpenFile($scriptFile) | Out-Null

    } else {
        $script = InvokeOperation $dteStartupProject $Environment $dteProject ScriptMigration @{
            fromMigration = $From
            toMigration = $To
            idempotent = [bool]$Idempotent
            contextType = $contextTypeName
        }
        try {
            # NOTE: Certain SKUs cannot create new SQL files, including xproj
            $window = $DTE.ItemOperations.NewFile('General\Sql File')
            $textDocument = $window.Document.Object('TextDocument')
            $editPoint = $textDocument.StartPoint.CreateEditPoint()
            $editPoint.Insert($script)
        }
        catch {
            $script | Out-File $scriptFile -Encoding utf8
            $DTE.ItemOperations.OpenFile($scriptFile) | Out-Null
        }
    }

    ShowConsole
}

#
# Remove-Migration
#

Register-TabExpansion Remove-Migration @{
    Context = { param ($tabExpansionContext) GetContextTypes $tabExpansionContext.Project $tabExpansionContext.StartupProject $tabExpansionContext.Environment }
    Project = { GetProjects }
    StartupProject = { GetProjects }
}

<#
.SYNOPSIS
    Removes the last migration.

.DESCRIPTION
    Removes the last migration.

.PARAMETER Context
    Specifies the DbContext to use. If omitted, the default DbContext is used.

.PARAMETER Project
    Specifies the project to use. If omitted, the default project is used.

.PARAMETER StartupProject
    Specifies the startup project to use. If omitted, the solution's startup project is used.

.PARAMETER Environment
    Specifies the environment to use. If omitted, "Development" is used.

.PARAMETER Force
    Removes the last migration without checking the database. If the last migration has been applied to the database, you will need to manually reverse the changes it made.

.LINK
    Add-Migration
    about_EntityFramework
#>
function Remove-Migration {
    [CmdletBinding(PositionalBinding = $false)]
    param ([string] $Context, [string] $Project, [string] $StartupProject, [string] $Environment, [switch] $Force)

    $values = ProcessCommonParameters $StartupProject $Project $Context
    $dteProject = $values.Project
    $contextTypeName = $values.ContextTypeName
    $dteStartupProject = $values.StartupProject
    $forceRemove = $Force -or (IsUwpProject $dteProject)

    if (IsDotNetProject $dteProject) {
        $options = ProcessCommonDotnetParameters $dteProject $dteStartupProject $Environment $contextTypeName
        if ($forceRemove) {
            $options += ,"--force"
        }
        InvokeDotNetEf $dteProject migrations remove @options | Out-Null
        Write-Output "Done."
    } else {
        $filesToRemove = InvokeOperation $dteStartupProject $Environment $dteProject RemoveMigration @{
            contextType = $contextTypeName
            force = [bool]$forceRemove
        }

        $filesToRemove | %{
            $projectItem = GetProjectItem $dteProject $_
            if ($projectItem) {
                $projectItem.Remove()
            }
        }
    }
}

#
# Scaffold-DbContext
#

Register-TabExpansion Scaffold-DbContext @{
    Provider = { param ($tabExpansionContext) GetProviders $tabExpansionContext.Project }
    Project = { GetProjects }
    StartupProject = { GetProjects }
}

<#
.SYNOPSIS
    Scaffolds a DbContext and entity type classes for a specified database.

.DESCRIPTION
    Scaffolds a DbContext and entity type classes for a specified database.

.PARAMETER Connection
    Specifies the connection string of the database.

.PARAMETER Provider
    Specifies the provider to use. For example, Microsoft.EntityFrameworkCore.SqlServer.

.PARAMETER OutputDir
    Specifies the directory to use to output the classes. If omitted, the top-level project directory is used.

.PARAMETER Context
    Specifies the name of the generated DbContext class.

.PARAMETER Schemas
    Specifies the schemas for which to generate classes.

.PARAMETER Tables
    Specifies the tables for which to generate classes.

.PARAMETER DataAnnotations
    Use DataAnnotation attributes to configure the model where possible. If omitted, the output code will use only the fluent API.

.PARAMETER Force
    Force scaffolding to overwrite existing files. Otherwise, the code will only proceed if no output files would be overwritten.

.PARAMETER Project
    Specifies the project to use. If omitted, the default project is used.

.PARAMETER StartupProject
    Specifies the startup project to use. If omitted, the solution's startup project is used.

.PARAMETER Environment
    Specifies the environment to use. If omitted, "Development" is used.

.LINK
    about_EntityFramework
#>
function Scaffold-DbContext {
    [CmdletBinding(PositionalBinding = $false)]
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string] $Connection,
        [Parameter(Position = 1, Mandatory =  $true)]
        [string] $Provider,
        [string] $OutputDir,
        [string] $Context,
        [string[]] $Schemas = @(),
        [string[]] $Tables = @(),
        [switch] $DataAnnotations,
        [switch] $Force,
        [string] $Project,
        [string] $StartupProject,
        [string] $Environment)

    $values = ProcessCommonParameters $StartupProject $Project
    $dteStartupProject = $values.StartupProject
    $dteProject = $values.Project

    if (IsDotNetProject $dteProject) {
        $options = ProcessCommonDotnetParameters $dteProject $dteStartupProject $Environment $Context
        if ($OutputDir) {
            $options += "--output-dir",(NormalizePath $OutputDir)
        }
        if ($DataAnnotations) {
            $options += ,"--data-annotations"
        }
        if ($Force) {
            $options += ,"--force"
        }
        $options += $Schemas | % { "--schema", $_ }
        $options += $Tables | % { "--table", $_ }

        InvokeDotNetEf $dteProject dbcontext scaffold $Connection $Provider @options | Out-Null
    } else {
        $artifacts = InvokeOperation $dteStartupProject $Environment $dteProject ReverseEngineer @{
            connectionString = $Connection
            provider = $Provider
            outputDir = $OutputDir
            dbContextClassName = $Context
            schemaFilters = $Schemas
            tableFilters = $Tables
            useDataAnnotations = [bool]$DataAnnotations
            overwriteFiles = [bool]$Force
        }

        $artifacts | %{ $dteProject.ProjectItems.AddFromFile($_) | Out-Null }
        $DTE.ItemOperations.OpenFile($artifacts[0]) | Out-Null

        ShowConsole
    }
}

#
# Enable-Migrations (Obsolete)
#

function Enable-Migrations {
    # TODO: Link to some docs on the changes to Migrations
    Write-Warning 'Enable-Migrations is obsolete. Use Add-Migration to start using Migrations.'
}

#
# (Private Helpers)
#

function GetProjects {
    $projects = Get-Project -All
    $groups = $projects | group Name

    return $projects | %{
        if ($groups | ? Name -eq $_.Name | ? Count -eq 1) {
            return $_.Name
        }

        return $_.ProjectName
    }
}

function GetContextTypes($projectName, $startupProjectName, $environment) {
    $values = ProcessCommonParameters $startupProjectName $projectName
    $startupProject = $values.StartupProject
    $project = $values.Project

    if (IsDotNetProject $startupProject) {
        $options = ProcessCommonDotnetParameters $startupProject $startupProject $environment
        $types = InvokeDotNetEf $startupProject -json -skipBuild dbcontext list @options
        return $types | %{ $_.fullName }
    } else {
        $contextTypes = InvokeOperation $startupProject $environment $project GetContextTypes -skipBuild
        return $contextTypes | %{ $_.SafeName }
    }
}

function GetMigrations($contextTypeName, $projectName, $startupProjectName, $environment) {
    $values = ProcessCommonParameters $startupProjectName $projectName $contextTypeName
    $startupProject = $values.StartupProject
    $project = $values.Project
    $contextTypeName = $values.ContextTypeName

    if (IsDotNetProject $startupProject) {
        $options = ProcessCommonDotnetParameters $startupProject $startupProject $environment $contextTypeName
        $migrations = InvokeDotNetEf $startupProject -json -skipBuild migrations list @options
        return $migrations | %{ $_.safeName }
    }
    else {
        $migrations = InvokeOperation $startupProject $environment $project GetMigrations @{ contextTypeName = $contextTypeName } -skipBuild
        return $migrations | %{ $_.SafeName }
    }
}

function ProcessCommonParameters($startupProjectName, $projectName, $contextTypeName) {
    $project = GetProject $projectName

    if (!$contextTypeName -and $project.ProjectName -eq $EFDefaultParameterValues.ProjectName) {
        $contextTypeName = $EFDefaultParameterValues.ContextTypeName
    }

    $startupProject = GetStartupProject $startupProjectName $project

    return @{
        Project = $project
        ContextTypeName = $contextTypeName
        StartupProject = $startupProject
    }
}

function NormalizePath($path) {
    try {
        $pathInfo = Resolve-Path -LiteralPath $path
        return $pathInfo.Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
    } 
    catch {
        # when directories don't exist yet
        return $path.TrimEnd([IO.Path]::DirectorySeparatorChar)
    }
}

function ProcessCommonDotnetParameters($dteProject, $dteStartupProject, $Environment, $contextTypeName) {
    $options=@()
    #if ($dteStartupProject.Name -ne $dteProject.Name) {
    #    $startupProjectPath = GetProperty $dteStartupProject.Properties FullPath
    #    $options += "--startup-project",(NormalizePath $startupProjectPath)
    #}
    if ($Environment) {
        $options += "--environment",$Environment
    }
    if ($contextTypeName) {
        $options += "--context",$contextTypeName
    }
    return $options
}

function IsDotNetProject($project) {
    $project.FileName -like "*.xproj"
}

function IsUwpProject($project) {
    $targetFrameworkMoniker = GetProperty $project.Properties TargetFrameworkMoniker
    $frameworkName = New-Object System.Runtime.Versioning.FrameworkName $targetFrameworkMoniker
    return $frameworkName.Identifier -eq '.NETCore'
}

function GetProject($projectName) {
    if ($projectName) {
        return Get-Project $projectName
    }

    return Get-Project
}

function ShowConsole {
    $componentModel = Get-VSComponentModel
    $powerConsoleWindow = $componentModel.GetService([NuGetConsole.IPowerConsoleWindow])
    $powerConsoleWindow.Show()
}

function InvokeDotNetEf($project, [switch] $json, [switch] $skipBuild) {
    $dotnet = (Get-Command dotnet).Source
    Write-Debug "Found $dotnet"
    $fullPath = GetProperty $project.Properties FullPath
    $projectJson = Join-Path $fullPath project.json
    try {
        Write-Debug "Reading $projectJson"
        $projectDef = Get-Content $projectJson -Raw | ConvertFrom-Json
    } catch {
        Write-Verbose $_.Exception.Message
        throw "Invalid JSON file in $projectJson"
    }
    if ($projectDef.tools) {
        $t=$projectDef.tools | Get-Member Microsoft.EntityFrameworkCore.Tools
    }
    if (!$t) {
        $projectName = $project.ProjectName
        throw "Cannot execute this command because 'Microsoft.EntityFrameworkCore.Tools' is not installed in project '$projectName'. Add 'Microsoft.EntityFrameworkCore.Tools' to the 'tools' section in project.json."
    }

    $output = $null

    $config = $project.ConfigurationManager.ActiveConfiguration.ConfigurationName
    $arguments = "--configuration", $config
    Write-Debug "Using configuration $config"

    $buildBasePath = GetProperty $project.ConfigurationManager.ActiveConfiguration.Properties OutputPath
    $arguments += "--build-base-path", $buildBasePath
    Write-Debug "Using build base path $buildBasePath"
    
    if ($skipBuild) {
        $arguments += ,"--no-build"
    }

    $arguments += $args

    # TODO better json output parsing so we don't need to suppress verbose output
    if ($json) {
        $arguments += ,"--json"
    } 
    else {
        $arguments += ,"--verbose"
    }
    
    $arguments = $arguments | ? { $_ } | % { if  ($_ -like '* *') { "'$_'" } else { $_ } }
    
    $command = "ef $($arguments -join ' ')"
    try {
        Write-Verbose "Working directory: $fullPath"
        Push-Location $fullPath
        $ErrorActionPreference='SilentlyContinue'
        Write-Verbose "Executing command: dotnet $command"
        $output = Invoke-Expression "& '$dotnet' $command" -ErrorVariable verboseOutput
        $exit = $LASTEXITCODE
        Write-Debug "Finish executing command with code $exit"
        if ($exit -ne 0) {
            if (!($verboseOutput) -and $output) {
                # most often occurs when Microsoft.EntityFrameworkCore.Tools didn't install
                throw $output
            }
            throw $verboseOutput
        }
        $output = $output -join [Environment]::NewLine

        Write-Debug $output
        if ($json) {
            Write-Debug "Parsing json output"
            # TODO trim the output of dotnet-build
            $match = [regex]::Match($output, "\[|\{")
            $output = $output.Substring($match.Index) | ConvertFrom-Json
        } else {
            Write-Verbose $output
        }

        # dotnet commands log verbose output to stderr
        Write-Verbose $($verboseOutput -join [Environment]::NewLine)
    }
    finally {
        $ErrorActionPreference='Stop'
        Pop-Location
    }
    return $output
}

function InvokeOperation($startupProject, $environment, $project, $operation, $arguments = @{}, [switch] $skipBuild) {
    $startupProjectName = $startupProject.ProjectName

    Write-Verbose "Using startup project '$startupProjectName'."

    $projectName = $project.ProjectName

    Write-Verbose "Using project '$projectName'"

    $package = Get-Package -ProjectName $startupProjectName | ? Id -eq Microsoft.EntityFrameworkCore.Tools
    if (!($package)) {
        throw "Cannot execute this command because Microsoft.EntityFrameworkCore.Tools is not installed in the startup project '$startupProjectName'."
    }

    if (!$skipBuild) {

        if (IsUwpProject $startupProject) {
            $config = $startupProject.ConfigurationManager.ActiveConfiguration.ConfigurationName
            $configProperties = $startupProject.ConfigurationManager.ActiveConfiguration.Properties
            $isNative = (GetProperty $configProperties ProjectN.UseDotNetNativeToolchain) -eq 'True'

            if ($isNative) {
                throw "Cannot run in '$config' mode because 'Compile with the .NET Native tool chain' is enabled. Disable this setting or use a different configuration and try again."
            }
        }

        Write-Verbose 'Build started...'

        # TODO: Only build required project. Don't use BuildProject, you can't specify platform
        $solutionBuild = $DTE.Solution.SolutionBuild
        $solutionBuild.Build($true)
        if ($solutionBuild.LastBuildInfo) {
            throw "Build failed."
        }

        Write-Verbose 'Build succeeded.'
    }

    if (![Type]::GetType('Microsoft.EntityFrameworkCore.Design.OperationResultHandler')) {
        Add-Type -Path (Join-Path $PSScriptRoot OperationHandlers.cs) -CompilerParameters (
            New-Object CodeDom.Compiler.CompilerParameters -Property @{
                CompilerOptions = '/d:NET451'
            })
    }

    $logHandler = New-Object Microsoft.EntityFrameworkCore.Design.OperationLogHandler @(
        { param ($message) Write-Error $message }
        { param ($message) Write-Warning $message }
        { param ($message) Write-Host $message }
        { param ($message) Write-Verbose $message }
        { param ($message) Write-Debug $message }
    )

    $properties = $project.Properties
    $fullPath = GetProperty $properties FullPath

    $startupOutputPath = GetProperty $startupProject.ConfigurationManager.ActiveConfiguration.Properties OutputPath
    $startupProperties = $startupProject.Properties
    $startupFullPath = GetProperty $startupProperties FullPath
    $startupTargetDir = Join-Path $startupFullPath $startupOutputPath

    $webConfig = GetProjectItem $startupProject 'Web.Config'
    $appConfig = GetProjectItem $startupProject 'App.Config'

    if ($webConfig) {
        $configurationFile = GetProperty $webConfig.Properties FullPath
        $dataDirectory = Join-Path $startupFullPath 'App_Data'
    }
    elseif ($appConfig) {
        $configurationFile = GetProperty $appConfig.Properties FullPath
    }

    Write-Verbose "Using application base '$startupTargetDir'."

    $info = New-Object AppDomainSetup -Property @{
        ApplicationBase = $startupTargetDir
        ShadowCopyFiles = 'true'
    }

    if ($configurationFile) {
        Write-Verbose "Using application configuration '$configurationFile'"
        $info.ConfigurationFile = $configurationFile
    }
    else {
        Write-Verbose 'No configuration file found.'
    }

    $domain = [AppDomain]::CreateDomain('EntityFrameworkDesignDomain', $null, $info)
    if ($dataDirectory) {
        Write-Verbose "Using data directory '$dataDirectory'"
        $domain.SetData('DataDirectory', $dataDirectory)
    }
    try {
        $commandsAssembly = 'Microsoft.EntityFrameworkCore.Tools'
        $operationExecutorTypeName = 'Microsoft.EntityFrameworkCore.Design.OperationExecutor'
        $targetAssemblyName = GetProperty $properties AssemblyName
        $startupAssemblyName = GetProperty $startupProperties AssemblyName
        $rootNamespace = GetProperty $properties RootNamespace

        $executor = $domain.CreateInstanceAndUnwrap(
            $commandsAssembly,
            $operationExecutorTypeName,
            $false,
            0,
            $null,
            @(
                [MarshalByRefObject]$logHandler,
                @{
                    startupTargetName = $startupAssemblyName
                    targetName = $targetAssemblyName
                    environment = $environment
                    projectDir = $fullPath
                    startupProjectDir = $startupFullPath
                    rootNamespace = $rootNamespace
                }
            ),
            $null,
            $null)

        $resultHandler = New-Object Microsoft.EntityFrameworkCore.Design.OperationResultHandler
        $currentDirectory = [IO.Directory]::GetCurrentDirectory()

        Write-Verbose "Using current directory '$startupTargetDir'."

        [IO.Directory]::SetCurrentDirectory($startupTargetDir)
        try {
            $domain.CreateInstance(
                $commandsAssembly,
                "$operationExecutorTypeName+$operation",
                $false,
                0,
                $null,
                ($executor, [MarshalByRefObject]$resultHandler, $arguments),
                $null,
                $null) | Out-Null
        }
        finally {
            [IO.Directory]::SetCurrentDirectory($currentDirectory)
        }
    }
    finally {
        [AppDomain]::Unload($domain)
    }

    if ($resultHandler.ErrorType) {
        if ($resultHandler.ErrorType -eq 'Microsoft.EntityFrameworkCore.Design.OperationException') {
            Write-Verbose $resultHandler.ErrorStackTrace
        }
        else {
            Write-Host $resultHandler.ErrorStackTrace
        }

        throw $resultHandler.ErrorMessage
    }
    if ($resultHandler.HasResult) {
        return $resultHandler.Result
    }
}

function GetProperty($properties, $propertyName) {
    $property = $properties.Item($propertyName)
    if (!$property) {
        return $null
    }

    return $property.Value
}

function GetProjectItem($project, $path) {
    $fullPath = GetProperty $project.Properties FullPath

    if (Split-Path $path -IsAbsolute) {
        $path = $path.Substring($fullPath.Length)
    }

    $itemDirectory = (Split-Path $path -Parent)

    $projectItems = $project.ProjectItems
    if ($itemDirectory) {
        $directories = $itemDirectory.Split('\')
        $directories | %{
            $projectItems = $projectItems.Item($_).ProjectItems
        }
    }

    $itemName = Split-Path $path -Leaf

    try {
        return $projectItems.Item($itemName)
    }
    catch [Exception] {
    }

    return $null
}

function GetStartUpProject($name, $fallbackProject) {
    if ($name) {
        if (IsDotNetProject $fallbackProject) {
            # this means users specified -StartupProject explicitly
            # otherwise, ignore what VS has marked as the "startup project"
            # TODO remove warning when https://github.com/aspnet/EntityFramework/issues/5311 is fixed
            Write-Warning "'-StartupProject' is not supported on *.xproj projects. This parameter will be ignored."
        }
        return Get-Project $name
    }

    $startupProjectPaths = $DTE.Solution.SolutionBuild.StartupProjects
    if ($startupProjectPaths) {
        if ($startupProjectPaths.Length -eq 1) {
            $startupProjectPath = $startupProjectPaths[0]
            if (!(Split-Path -IsAbsolute $startupProjectPath)) {
                $solutionPath = Split-Path (GetProperty $DTE.Solution.Properties Path)
                $startupProjectPath = Join-Path $solutionPath $startupProjectPath -Resolve
            }

            $startupProject = GetSolutionProjects | ?{
                try {
                    $fullName = $_.FullName
                }
                catch [NotImplementedException] {
                    return $false
                }

                if ($fullName -and $fullName.EndsWith('\')) {
                    $fullName = $fullName.Substring(0, $fullName.Length - 1)
                }

                return $fullName -eq $startupProjectPath
            }
            if ($startupProject) {
                return $startupProject
            }

            Write-Warning "Unable to resolve startup project '$startupProjectPath'."
        }
        else {
            Write-Verbose 'More than one startup project found.'
        }
    }
    else {
        Write-Verbose 'No startup project found.'
    }

    return $fallbackProject
}

function GetSolutionProjects() {
    $projects = New-Object System.Collections.Stack

    $DTE.Solution.Projects | %{
        $projects.Push($_)
    }

    while ($projects.Count -ne 0) {
        $project = $projects.Pop();

        # NOTE: This line is similar to doing a "yield return" in C#
        $project

        if ($project.ProjectItems) {
            $project.ProjectItems | ?{ $_.SubProject } | %{
                $projects.Push($_.SubProject)
            }
        }
    }
}

function GetProviders($projectName) {
    if (!($projectName)) {
        $projectName = (Get-Project).ProjectName
    }

    return Get-Package -ProjectName $projectName | select -ExpandProperty Id
}


# SIG # Begin signature block
# MIIkCwYJKoZIhvcNAQcCoIIj/DCCI/gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCgizDxftMeB1yD
# asOO8hEmknIG1AdW1bFZQ5dRaR0Zt6CCDZIwggYQMIID+KADAgECAhMzAAAAZEeE
# lIbbQRk4AAAAAABkMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMTUxMDI4MjAzMTQ2WhcNMTcwMTI4MjAzMTQ2WjCBgzEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9Q
# UjEeMBwGA1UEAxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAky7a2OY+mNkbD2RfTahYTRQ793qE/DwRMTrvicJK
# LUGlSF3dEp7vq2YoNNV9KlV7TE2K8sDxstNSFYu2swi4i1AL3X/7agmg3GcExPHf
# vHUYIEC+eCyZVt3u9S7dPkL5Wh8wrgEUirCCtVGg4m1l/vcYCo0wbU06p8XzNi3u
# XyygkgCxHEziy/f/JCV/14/A3ZduzrIXtsccRKckyn6B5uYxuRbZXT7RaO6+zUjQ
# hiyu3A4hwcCKw+4bk1kT9sY7gHIYiFP7q78wPqB3vVKIv3rY6LCTraEbjNR+phBQ
# EL7hyBxk+ocu+8RHZhbAhHs2r1+6hURsAg8t4LAOG6I+JQIDAQABo4IBfzCCAXsw
# HwYDVR0lBBgwFgYIKwYBBQUHAwMGCisGAQQBgjdMCAEwHQYDVR0OBBYEFFhWcQTw
# vbsz9YNozOeARvdXr9IiMFEGA1UdEQRKMEikRjBEMQ0wCwYDVQQLEwRNT1BSMTMw
# MQYDVQQFEyozMTY0Mis0OWU4YzNmMy0yMzU5LTQ3ZjYtYTNiZS02YzhjNDc1MWM0
# YjYwHwYDVR0jBBgwFoAUSG5k5VAF04KqFzc3IrVtqMp1ApUwVAYDVR0fBE0wSzBJ
# oEegRYZDaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljQ29k
# U2lnUENBMjAxMV8yMDExLTA3LTA4LmNybDBhBggrBgEFBQcBAQRVMFMwUQYIKwYB
# BQUHMAKGRWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# Q29kU2lnUENBMjAxMV8yMDExLTA3LTA4LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqG
# SIb3DQEBCwUAA4ICAQCI4gxkQx3dXK6MO4UktZ1A1r1mrFtXNdn06DrARZkQTdu0
# kOTLdlGBCfCzk0309RLkvUgnFKpvLddrg9TGp3n80yUbRsp2AogyrlBU+gP5ggHF
# i7NjGEpj5bH+FDsMw9PygLg8JelgsvBVudw1SgUt625nY7w1vrwk+cDd58TvAyJQ
# FAW1zJ+0ySgB9lu2vwg0NKetOyL7dxe3KoRLaztUcqXoYW5CkI+Mv3m8HOeqlhyf
# FTYxPB5YXyQJPKQJYh8zC9b90JXLT7raM7mQ94ygDuFmlaiZ+QSUR3XVupdEngrm
# ZgUB5jX13M+Pl2Vv7PPFU3xlo3Uhj1wtupNC81epoxGhJ0tRuLdEajD/dCZ0xIni
# esRXCKSC4HCL3BMnSwVXtIoj/QFymFYwD5+sAZuvRSgkKyD1rDA7MPcEI2i/Bh5O
# MAo9App4sR0Gp049oSkXNhvRi/au7QG6NJBTSBbNBGJG8Qp+5QThKoQUk8mj0ugr
# 4yWRsA9JTbmqVw7u9suB5OKYBMUN4hL/yI+aFVsE/KJInvnxSzXJ1YHka45ADYMK
# AMl+fLdIqm3nx6rIN0RkoDAbvTAAXGehUCsIod049A1T3IJyUJXt3OsTd3WabhIB
# XICYfxMg10naaWcyUePgW3+VwP0XLKu4O1+8ZeGyaDSi33GnzmmyYacX3BTqMDCC
# B3owggVioAMCAQICCmEOkNIAAAAAAAMwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29m
# dCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDExMB4XDTExMDcwODIwNTkw
# OVoXDTI2MDcwODIxMDkwOVowfjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAx
# MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKvw+nIQHC6t2G6qghBN
# NLrytlghn0IbKmvpWlCquAY4GgRJun/DDB7dN2vGEtgL8DjCmQawyDnVARQxQtOJ
# DXlkh36UYCRsr55JnOloXtLfm1OyCizDr9mpK656Ca/XllnKYBoF6WZ26DJSJhIv
# 56sIUM+zRLdd2MQuA3WraPPLbfM6XKEW9Ea64DhkrG5kNXimoGMPLdNAk/jj3gcN
# 1Vx5pUkp5w2+oBN3vpQ97/vjK1oQH01WKKJ6cuASOrdJXtjt7UORg9l7snuGG9k+
# sYxd6IlPhBryoS9Z5JA7La4zWMW3Pv4y07MDPbGyr5I4ftKdgCz1TlaRITUlwzlu
# ZH9TupwPrRkjhMv0ugOGjfdf8NBSv4yUh7zAIXQlXxgotswnKDglmDlKNs98sZKu
# HCOnqWbsYR9q4ShJnV+I4iVd0yFLPlLEtVc/JAPw0XpbL9Uj43BdD1FGd7P4AOG8
# rAKCX9vAFbO9G9RVS+c5oQ/pI0m8GLhEfEXkwcNyeuBy5yTfv0aZxe/CHFfbg43s
# TUkwp6uO3+xbn6/83bBm4sGXgXvt1u1L50kppxMopqd9Z4DmimJ4X7IvhNdXnFy/
# dygo8e1twyiPLI9AN0/B4YVEicQJTMXUpUMvdJX3bvh4IFgsE11glZo+TzOE2rCI
# F96eTvSWsLxGoGyY0uDWiIwLAgMBAAGjggHtMIIB6TAQBgkrBgEEAYI3FQEEAwIB
# ADAdBgNVHQ4EFgQUSG5k5VAF04KqFzc3IrVtqMp1ApUwGQYJKwYBBAGCNxQCBAwe
# CgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0j
# BBgwFoAUci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0
# cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2Vy
# QXV0MjAxMV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAwTgYIKwYBBQUH
# MAKGQmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2Vy
# QXV0MjAxMV8yMDExXzAzXzIyLmNydDCBnwYDVR0gBIGXMIGUMIGRBgkrBgEEAYI3
# LgMwgYMwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvZG9jcy9wcmltYXJ5Y3BzLmh0bTBABggrBgEFBQcCAjA0HjIgHQBMAGUAZwBh
# AGwAXwBwAG8AbABpAGMAeQBfAHMAdABhAHQAZQBtAGUAbgB0AC4gHTANBgkqhkiG
# 9w0BAQsFAAOCAgEAZ/KGpZjgVHkaLtPYdGcimwuWEeFjkplCln3SeQyQwWVfLiw+
# +MNy0W2D/r4/6ArKO79HqaPzadtjvyI1pZddZYSQfYtGUFXYDJJ80hpLHPM8QotS
# 0LD9a+M+By4pm+Y9G6XUtR13lDni6WTJRD14eiPzE32mkHSDjfTLJgJGKsKKELuk
# qQUMm+1o+mgulaAqPyprWEljHwlpblqYluSD9MCP80Yr3vw70L01724lruWvJ+3Q
# 3fMOr5kol5hNDj0L8giJ1h/DMhji8MUtzluetEk5CsYKwsatruWy2dsViFFFWDgy
# cScaf7H0J/jeLDogaZiyWYlobm+nt3TDQAUGpgEqKD6CPxNNZgvAs0314Y9/HG8V
# fUWnduVAKmWjw11SYobDHWM2l4bf2vP48hahmifhzaWX0O5dY0HjWwechz4GdwbR
# BrF1HxS+YWG18NzGGwS+30HHDiju3mUv7Jf2oVyW2ADWoUa9WfOXpQlLSBCZgB/Q
# ACnFsZulP0V3HjXG0qKin3p6IvpIlR+r+0cjgPWe+L9rt0uX4ut1eBrs6jeZeRhL
# /9azI2h15q/6/IvrC4DqaTuv/DDtBEyO3991bWORPdGdVk5Pv4BXIqF4ETIheu9B
# CrE/+6jMpF3BoYibV3FWTkhFwELJm3ZbCoBIa/15n8G9bW1qyVJzEw16UM0xghXP
# MIIVywIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExAhMzAAAA
# ZEeElIbbQRk4AAAAAABkMA0GCWCGSAFlAwQCAQUAoIG6MBkGCSqGSIb3DQEJAzEM
# BgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqG
# SIb3DQEJBDEiBCBYZ9nhSjFK+0/Cakihxh+sitSl7Tve4KHuYNiPIwzRHjBOBgor
# BgEEAYI3AgEMMUAwPqAkgCIATQBpAGMAcgBvAHMAbwBmAHQAIABBAFMAUAAuAE4A
# RQBUoRaAFGh0dHA6Ly93d3cuYXNwLm5ldC8gMA0GCSqGSIb3DQEBAQUABIIBAC/e
# ac93qok8JDXLdVf/dGpmZILgCb7PoZITT0xTKJ1nG+2VmqfvUq6EbpGJiO1iLX13
# XR3mCHB1y5hTvYKN+h/ZDtb5o6i7QTHEzIaxQJrgJ5TGm2TjUKHa+pymcQgdgVZr
# KYACJj7gSdwQdD2LQSvObiymBSiYUI0krOgvyVd1fFr5v0qHw4pInGM6km7OySKV
# QXT+W31Mc8qF874+q12IN2qp7hZuHXWC78BbjAa5NlvdjwTmXcMK03ibQCgjoEZu
# MLJZakKlA8IUh2i8pje50BfGvob5GLNqbV4hFrSNr/CJO2beZpHz2AvhhC5QXgxw
# ejLyW0H6f2nefW+Qy66hghNNMIITSQYKKwYBBAGCNwMDATGCEzkwghM1BgkqhkiG
# 9w0BBwKgghMmMIITIgIBAzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQ
# AQSgggEsBIIBKDCCASQCAQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQg
# MNMf+fnfqSFCmiUScJSQgIJayEUg8yCFOitgk75vBxgCBlchVcpFqxgTMjAxNjA1
# MTIyMTE5MjkuMjEyWjAHAgEBgAIB9KCBuaSBtjCBszELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNp
# cGhlciBEU0UgRVNOOjU4NDctRjc2MS00RjcwMSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNloIIO0DCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIw
# DQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhv
# cml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1NVowfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
# ggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD5WHC
# drc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ldk6zW
# czBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3RYRNu
# KMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2KQk1AUdEPnAY+
# Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6p/Tc
# ZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQBgkrBgEEAYI3
# FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYBBAGC
# NxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8w
# HwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmg
# R4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWlj
# Um9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEF
# BQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29D
# ZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYBBAGC
# Ny4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUEtJ
# L2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEA
# bABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3
# DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn++ldtGTCz
# wsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbMQEBBm9xcF/9c
# +V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvkx872
# ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp8c6Z
# ZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S4Zz5Hfw42JT0
# xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3aicaoGig+JFrph
# pxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf5zEHpJM692VH
# eOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb2sgN
# VZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJzxlBTeCG+Sqa
# oxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M5k37
# Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNow
# ggPCoAMCAQICEzMAAACIY6yEwV4WyhAAAAAAAIgwDQYJKoZIhvcNAQELBQAwfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwMzMwMTkyNDI1WhcNMTcw
# NjMwMTkyNDI1WjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjU4NDct
# Rjc2MS00RjcwMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAkn2hNNxVuaX1iN34vWsn
# jK8n7HY1Q3m0Ft6ki6E6y8kls7WFYH1uOrv6PR+f9UEOlXmOANdYWMP8W2xT7mmd
# Ba3if0ajLcxXNo7vSXoc3r30pC2pZjHQjonemXgoEh6VxpNMeOAQfE2eizBHe47q
# 0q1l7T2qe+Ia1o8/YnY1DCKInVT75ssrQCeiL/YeOqv99pUuJWRxKIlynkc0AVNi
# rglrq+IslNNWwZKIrYBcSSWiRNCQ3DkKz6SIexhQNm4muodcebnE0U5B8adABuyB
# oYXHFnezS39tiSFk8z3Ti9NLYpTLawHlgNgM9+G5/xYsZr1tCYeNw5RqvDfMEPsi
# nQIDAQABo4IBGzCCARcwHQYDVR0OBBYEFAHmNgqRng7pG6TKR+oxvkmfq5gEMB8G
# A1UdIwQYMBaAFNVjOlyKMZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeG
# RWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Rp
# bVN0YVBDQV8yMDEwLTA3LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUH
# MAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3Rh
# UENBXzIwMTAtMDctMDEuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYB
# BQUHAwgwDQYJKoZIhvcNAQELBQADggEBAA7A6X6JPQwrixQkH6GX58tybufzYd82
# MG6xKXohCgPVp5zkAQWOwiXfBaY38m0pA0VR4ZFX8Qw4SdISDJqj8Ntbd0HosGLr
# QHvJcGPfJFx/l+5YpzIYAe+y7av3QN6C2MPBAwtQFHF3jcWWgh9ZMpmtty53zcAQ
# pXM+Llak7s21J2yvL9m+qE5TxgkTlFuYPBZ9py8jc3O4j/mmnmLEvglXqHK/htOt
# VgnJxWdnuSKoGJ1wHm0mPGV7hEa61ADypHIqonMYAWPBxRLIFJV9GdvTJQqyqWip
# Q8f1f2e4gySm+zc/1oLbEeDjMxvrNL16BvnIC8EEO5jglG7VYlmvdh6hggN5MIIC
# YQIBATCB46GBuaSBtjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjU4
# NDctRjc2MS00RjcwMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
# aWNloiUKAQEwCQYFKw4DAhoFAAMVAP0b508bJkUL/mSqni0xiwXSDNwhoIHCMIG/
# pIG8MIG5MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYD
# VQQLEwRNT1BSMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046NERFOS0wQzVFLTNF
# MDkxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2sw
# DQYJKoZIhvcNAQEFBQACBQDa3zRoMCIYDzIwMTYwNTEyMTY1NzEyWhgPMjAxNjA1
# MTMxNjU3MTJaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFANrfNGgCAQAwCgIBAAIC
# LOMCAf8wBwIBAAICHWAwCgIFANrghegCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYK
# KwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUF
# AAOCAQEAqgv03rnWJMEp+qD5+27Nwm/7f6XyjTppeuR1O/CHoliPWFRkT2vMnvY2
# lFySwFkjhZKun5is2UqwLW0xaO+TIxgQNB3gnq2WtWMn3M2W4uI684WV1kWjhfy7
# dDXQgrC1+MCk5A2XCj/7b5oxyuEX0iPg9Z9alxqu06DAGkeyocunuvxEgtJaU077
# Nffac5zSCoO3WIBCedeSfrWlBanro//14wMh5h7bNcnMlFWTdBUs8TCxgs9lrd9h
# 6qtBKaW2s/0cXoF9YQMqw9cQlNOnaf+Eb63ZPM2vw5X0T/VraZrv0Gflgh24Le7d
# Yr1ndHXON1faOB6y3TReUddVYoCUWDGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAiGOshMFeFsoQAAAAAACIMA0GCWCGSAFl
# AwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIL6Zio6Zn9cApZBAkRqdk8lfLJnopxCcvvmfgAvpRAVcMIHiBgsqhkiG
# 9w0BCRACDDGB0jCBzzCBzDCBsQQU/RvnTxsmRQv+ZKqeLTGLBdIM3CEwgZgwgYCk
# fjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAIhjrITBXhbKEAAA
# AAAAiDAWBBQOIyfcIxiXhf7yWesMtx4cKMCXAjANBgkqhkiG9w0BAQsFAASCAQAP
# awrrDAus6m0wjyLvwbpyaGNfd+VlwHFA2g/4EujU0tDliMg3FGzAZi8w9heQ/PQ9
# hX6McDtjIVkv/mR2h9vwW01lneAifS+dyMAAY5ZD3JAvwMiYZ/Q8DgwPfbAZii/t
# 50Hi+MDDyWTb8+BZoE9E8mBZPg79h4rdumsaU/C19WliESa6I5Kcmp9coPxKzsuo
# mkBwGQcV80Xi7EUIlVIPfxV8NeEO9jihTiIttaG4gnYeoMb2hzdotbIQ0ce3ixQI
# BaEPuJyqXRdUEcs8zUBIb8D1QV7bieEbIb/zstUZxFzK/NiGDI18V18a1Ox3XyXS
# J90Bb2wXTaSfQMs3kgHo
# SIG # End signature block
