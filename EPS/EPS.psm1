#######################################################
##
##  EPS - Embedded PowerShell
##  Dave Wu, June 2014
##
##  Templating tool for PowerShell
##  For detailed usage please refer to:
##  http://straightdave.github.io/eps
##
#######################################################

Set-StrictMode -Version Latest

$execPath   = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$thisfile   = "$execPath\eps.psm1"
$sysLibFile = "$execPath\sys_lib.ps1"  # import built-in resources to eps file 
$p = [regex]'(?si)(?<content>.*?)(?<token><%%|%%>|<%=|<%#|<%@|<%|%>|\n)'
$rxDirective = [regex]'(?i)\s*(?<Directive>\w+)(?<Argument>\s*(?:\w+="[^""]+"))*\s*$'

<#

.SYNOPSIS
  Expand text template

.DESCRIPTION
   Key entrance of EPS

.PARAMETER template

.PARAMETER file
  
.PARAMETER binding
  The context in which the expansion will be performed.

  If a hastable is passed variables will eb created named according
  to the keys of the hashtable and the values bound to the keys in
  the hashtable.

  If an simple object is passed a variable named according to the
  ModelVariableName parameter will be created receivind the value
  passed in.

.PARAMETER safe 
   Safe mode: start a new/isolated PowerShell instance to compile the templates    
   to prevent result from being polluted by variables in current context
   With Safe mode: you can pass a hashtable containing all variables to this function. 
   Compiling process will inject values recorded in hashtable to template

.PARAMETER ModelVariableName
  The 

.EXAMPLE
   Expand-Template -template $text
   will use current context to fill variables in template. If no '$name' exists in current context, it will produce blanks.

.EXAMPLE
   Expand-Template -template $text -safe -binding @{ name = "dave" }
   
   will use "dave" to render the placeholder "<%= $name %>" in template

.EXAMPLE
   $result = Expand-Template -file $a_file -safe -binding @{ name = "dave" }
   *Note*: here using safe mode

   or

   $text = @'
   Dave is a <% if($true){ %>man<% }else{ %>lady<% } %>.
   Davie is <%= $age %>.
   '@
   
   $age = 26
   $result = Expand-Template -template $text
#>
function Expand-Template {
  [CmdletBinding()]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingInvokeExpression", "")]
  Param(
    [Parameter(Mandatory=$true, ParameterSetName="ByTemplate")]
    [ValidateNotNullOrEmpty()]
    [string]$Template,

    [Parameter(Mandatory=$true, ParameterSetName="ByFile")]
    [ValidateNotNullOrEmpty()]
    [string]$File,

    [Parameter(ValueFromPipeline=$True, ValueFromPipelinebyPropertyName=$True)]
    $binding = @{},
    
    [Parameter(Mandatory=$false)]
    [switch]$safe,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$ModelVariableName = "model"
  )
  
  BEGIN {
    switch ($PSCmdlet.ParameterSetName) {
      "ByFile" {
        $File = Resolve-Path $File -ErrorAction:Stop
        # for relative path in @Import directive we must change
        # current location to the directory of the template file
        $Template = (Get-Content $File) -join "`n"
        Push-Location (Split-Path -Parent $File)
      }
    }

    
    if($sysLibFile -and (test-path $sysLibFile)){
      $Template = "<% . $sysLibFile %>`n" + $Template  
    }

    if (-not $safe) {
        $script = Compile-Raw $template
    }
  }
  
  PROCESS {
    if($safe) {
      $p = [powershell]::create()
      
      $block = {
        param(
          $temp,
          $lib,
          $binding = @{},    # variable binding
          $ModelVariableName
        )
        
        . $lib   # load Compile-Raw

        if ($binding -is [Hashtable]) {
          $binding.keys | ForEach-Object { New-Variable -Name $_ -Value $binding[$_] }     
        } else {
          New-Variable -Name $ModelVariableName -Value $binding
        }
        
        $script = Compile-Raw $temp      
        Invoke-Expression $script      
      }
      
      [void]$p.addscript($block)
      [void]$p.addparameter("temp",$Template)
      [void]$p.addparameter("lib",$thisfile)
      [void]$p.addparameter("binding",$binding)
      [void]$p.addparameter("ModelVariableName",$ModelVariableName)
      $p.invoke()
    } else {
      if ($binding -is [Hashtable]) {
        $binding.keys | ForEach-Object { New-Variable -Name $_ -Value $binding[$_] }     
      } else {
        New-Variable -Name $ModelVariableName -Value $binding
      }

      Invoke-Expression $script
    }
  } 
  
  END {
      if ($PSCmdlet.ParameterSetName -eq "ByFile") {
        Pop-Location
      }
  }
}

## Compile-Raw:
##
##   Used internally. To comiple templates into text
##   Input parameter '$raw' should be a [string] type.
##   So if reading from a file via 'gc/get-content' cmdlet, 
##   you should join all lines together with new-line ("`n") as delimiters
##
function Compile-Raw{
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$raw
  )

  #========================
  # constants
  #========================
  $pre_cmd = @('$_temp = ""')
  $post_cmd = @('$_temp')
  $put_cmd = '$_temp += '
  $insert_cmd = '$_temp += ' 
  
  #========================
  # 'global' variables
  #========================
  $content = ''
  $stag = ''  # start tag
  $line = @()
  $w = $false # whether last tag-pair is <% %>
  
  #========================
  # start!
  #========================
  $pre_cmd | ForEach-Object { $line += $_ }
  $raw += "`n"
  
  $m = $p.match($raw)
  while($m.success){
    $content = $m.groups["content"].value
    $token = $m.groups["token"].value
    
    if($stag -eq ''){
      
      # escaping characters
      $content = $content -replace '([`"$])', '`$1'
    
      switch($token){
        { '<%', '<%=', '<%#', '<%@' -contains $_ } {
          $stag = $token          
        }
        
        "`n" {
          if( -not $w ) { 
            $content += '`n'
          }
        }
        
        '<%%' {
          $content += '<%'
        }
        
        '%%>' {
          $content += '%>'
        }
        
        default {
          $content += $token
        }
      }
      
      $w = $false
    } 
    else{
      switch($token){
        '%>' {          
          switch($stag){
            '<%' {
              $line += $content
              $w = $true
            }
            
            '<%=' {
              $line += ($insert_cmd + '"$(' + $content.trim() + ')"')
            }
            
            '<%#' { }

            '<%@' { 
                $directive = Get-Directive $content
                if (-not $directive) {
                    Write-Error ("Syntax error in directive [$content]") -ErrorAction:Stop
                }
                switch ($directive.Name) {
                  "Import" {
                    if (-not $directive.Arguments.ContainsKey("src")) {
                        Write-Error ("No argument 'src' specified for @Import ") -ErrorAction:Stop
                    }
                    $impFile = Resolve-Path $directive.Arguments["src"] -ErrorAction:Stop
                    $impCode = Compile-Raw ((Get-Content $impFile) -join "`n")
                    $line += ($insert_cmd + '& {' + $impCode + '}')
                  }
                  default {
                    Write-Error ("Unsupported directive [$($directive.Name)]") -ErrorAction:Stop
                  }
                } 
                $w = $true
            }
          }
          
          $stag = ''
          $content = ''
        }
        
        "`n" {
          if($stag -eq '<%' -and $content -ne ''){            
            $line += $content
          }
          $content = ''
        }
        
        default {
          $content += $token
        }
      }
    }
    
    if( $content -ne '') { $line += ($put_cmd + '"' + $content + '"') }
    $m = $m.nextMatch()
  }
  
  $post_cmd | ForEach-Object { $line += $_ }
  $script = ($line -join ';')
  
  #Write-Debug $line

  $line = $null
  $script
}

function Get-Directive {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Directive
  )
  
  PROCESS {
    $m = $rxDirective.Match($Directive)
    if ($m.Success) {
        $args = @{}
        if ($m.Groups["Argument"]) {
            foreach ($argStr in $m.Groups["Argument"].Captures) {
                $argTuple = $argStr.Value.Split("=")
                $args[$argTuple[0].Trim()] = $argTuple[1].Replace("""", "").Trim()
            }
        }
        New-Object psobject -Property @{
          Name = $m.Groups["Directive"].Value;
          Arguments = $args;
        }
    }
  }
  
}