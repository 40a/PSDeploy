﻿Function Get-PSDeployment {
    <#
    .SYNOPSIS
        Read a Deployment.yml file

    .DESCRIPTION
        Read a Deployment.yml file

        The resulting object contains these properties
            DeploymentSource  = Path to the deployment.yml
            DeploymentName    = Deployment name
            DeploymentAuthor  = Optional deployment author
            DeploymentType    = Type of deployment, must be defined in PSDeploy.yml
            DeploymentOptions = Options for this deploymenttype
            Source            = Path to source from the local machine
            SourceType        = Directory or file
            SourceExists      = Whether we can test path against the local source
            Targets           = One or more targets to deploy to.
            Raw               = Raw definition for this deployment, feel free to go wild.

        This is oriented around deployments from a Windows system.

        It's a poor schema that grew from a single use case.
        Included 'Raw', allowing you to do whatever you want : )

    .PARAMETER Path
        Path to deployment.yml to parse

    .PARAMETER DeploymentRoot
        Assumed root of the deployment.yml for relative paths. Default is the parent of deployment.yml

    .PARAMETER Tags
        Only return deployments with all of the specified Tags (like -and, not -or)

    .EXAMPLE
        Get-PSDeployment C:\Git\Module1\Deployments.yml

        # Get deployments from a yml file

    .EXAMPLE
        Get-PSDeployment -Path C:\Git\Module1\Deployments.yml, C:\Git\Module2\Deployments.yml |
            Invoke-PSDeployment -Force

        # Get deployments from two files, invoke deployment for all

    .EXAMPLE
        Get-PSDeployment -Path C:\Git\Module1\My.PSDeploy.ps1 -Tags Prod, Azure

        # Get deployments from My.PSDeploy.ps1, including only those tagged both 'prod' and 'azure'

    .LINK
        about_PSDeploy

    .LINK
        https://github.com/RamblingCookieMonster/PSDeploy

    .LINK
        Invoke-PSDeployment

    .LINK
        Invoke-PSDeploy

    .LINK
        Get-PSDeploymentType

    .LINK
        Get-PSDeploymentScript

    #>
    [cmdletbinding(DefaultParameterSetName='File')]
    Param(
        [validatescript({Test-Path -Path $_ -PathType Leaf -ErrorAction Stop})]
        [parameter( ParameterSetName = 'File',
                    Mandatory = $True)]
        [string[]]$Path,

        [string]$DeploymentRoot,

        [parameter( ParameterSetName = 'Deployment',
                    Mandatory = $True)]
        [object[]]$Deployment,

        [string[]]$Tags
    )

    #Resolve relative paths... Thanks Oisin! http://stackoverflow.com/a/3040982/3067642
    if($PSBoundParameters.ContainsKey('DeploymentRoot'))
    {
        $DeploymentRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DeploymentRoot)
    }

    # Everything below here needs refactoring.
        # We assume on psdeploy.ps1 means all paths are psdeploy.ps1
        # Will anyone specify a mix of yml, ps1?
        # Source path might not be testable for all resources
        # Avoid code re-use if it makes sense
        # Fix all the odd scoping

    $TagParam = @{}
    if( $PSBoundParameters.ContainsKey('Tags') )
    {
        $TagParam.Add('Tags',@($Tags))
    }

    # Handle PSDeploy.ps1 parsing
    if($PSCmdlet.ParameterSetName -eq 'File' -and $Path -like "*.psdeploy.ps1" )
    {
        foreach($DeploymentFile in $Path)
        {
            $DeploymentFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DeploymentFile)
            if(-not $PSBoundParameters.ContainsKey('DeploymentRoot'))
            {
                $DeploymentRoot = Split-Path $DeploymentFile -parent
            }

            $Script:Deployments = [ordered]@{}
            . $DeploymentFile
            Foreach($key in $Script:Deployments.Keys)
            {
                Get-PSDeployment -Deployment $([pscustomobject]$Script:Deployments.$Key) -DeploymentRoot $DeploymentRoot @TagParam
            }
        }
        return
    }
    # Handle yaml and deployment object parsing
    elseif($PSCmdlet.ParameterSetName -eq 'File')
    {
        # This parses a deployment YML
        foreach($DeploymentFile in $Path)
        {
            #Resolve relative paths... Thanks Oisin! http://stackoverflow.com/a/3040982/3067642
            $DeploymentFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DeploymentFile)

            if(-not $DeploymentRoot)
            {
                $DeploymentRoot = Split-Path $DeploymentFile -parent
            }

            if(-not (Test-Path $DeploymentRoot -PathType Container))
            {
                Write-Error "Skipping '$DeploymentFile', could not validate DeploymentRoot '$DeploymentRoot'"
            }

            $Deployments = ConvertFrom-Yaml -Path $DeploymentFile

            $DeploymentMap = foreach($DeploymentName in $Deployments.keys)
            {
                $DeploymentHash = $Deployments.$DeploymentName
                $Sources = @($DeploymentHash.Source)

                #TODO: Move this, not applicable to all deployment types
                foreach($Source in $Sources)
                {
                    #Determine the path to this source. Try absolute, fall back on relative
                    if(Test-Path $Source -ErrorAction SilentlyContinue)
                    {
                        $LocalSource = ( Resolve-Path $Source ).Path
                    }
                    else
                    {
                       $LocalSource = Join-Path $DeploymentRoot $Source
                    }

                    $Exists = Test-Path $LocalSource
                    if($Exists)
                    {
                        $Item = Get-Item $LocalSource
                        if($Item.PSIsContainer)
                        {
                            $Type = 'Directory'
                        }
                        else
                        {
                            $Type = 'File'
                        }
                    }

                    [pscustomobject]@{
                        DeploymentFile = $DeploymentFile
                        DeploymentName = $DeploymentName
                        DeploymentAuthor = $DeploymentHash.Author
                        DeploymentType = $DeploymentHash.DeploymentType
                        DeploymentOptions = $DeploymentHash.Options
                        Source = $LocalSource
                        SourceType = $Type
                        SourceExists = $Exists
                        Targets = @($DeploymentHash.Destination)
                        Tags = $DeploymentHash.Tags
                        Dependencies = $DeploymentHash.Dependencies
                        Raw = $DeploymentHash
                    }
                }
            }
        }
    }
    elseif($PSCmdlet.ParameterSetName -eq 'Deployment')
    {
        $DeploymentMap = Foreach($DeploymentItem in $Deployment)
        {
            # TODO: This should be abstracted out, and use the same code that file parameterset uses...
            $Sources = @($DeploymentItem.Source)

            #TODO: Move this, not applicable to all deployment types
            foreach($Source in $Sources)
            {
                #Determine the path to this source. Try absolute, fall back on relative
                if(Test-Path $Source -ErrorAction SilentlyContinue)
                {
                    $LocalSource = ( Resolve-Path $Source ).Path
                }
                else
                {
                    $LocalSource = Join-Path $DeploymentRoot $Source
                }

                $Exists = Test-Path $LocalSource
                if($Exists)
                {
                    $Item = Get-Item $LocalSource
                    if($Item.PSIsContainer)
                    {
                        $Type = 'Directory'
                    }
                    else
                    {
                        $Type = 'File'
                    }
                }

                [pscustomobject]@{
                    DeploymentFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DeploymentFile)
                    DeploymentName = $DeploymentItem.DeploymentName
                    DeploymentType = $DeploymentItem.DeploymentType
                    DeploymentOptions = $DeploymentItem.DeploymentOptions
                    Source = $LocalSource
                    SourceType = $Type
                    SourceExists = $Exists
                    Targets = $DeploymentItem.Targets
                    Tags = $DeploymentItem.Tags
                    Dependencies = $DeploymentItem.Dependencies
                    Raw = $null
                }
            }
        }
    }

    if( @($DeploymentMap.SourceExists) -contains $false)
    {
        Write-Error "Nonexistent paths found:`n`n$($DeploymentMap | Where {-not $_.SourceExists} | Format-List | Out-String)`n"
    }

    If($PSBoundParameters.ContainsKey('Tags'))
    {
        $DeploymentMap = Get-TaggedDeployment -Deployment $DeploymentMap @TagParam
    }

    $DeploymentMap | Add-ObjectDetail -TypeName 'PSDeploy.Deployment'
}