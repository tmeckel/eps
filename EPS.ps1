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

$execPath = $MyInvocation.MyCommand.Definition

## EPS-Render:
##
##   Key entrance of EPS
##   Safe mode: start a new/isolated PowerShell instance to compile the templates 
##   to prevent result from being polluted by variables in current context
##   With Safe mode: you can pass a hashtable containing all variables to this function. 
##   Compiling process will inject values recorded in hashtable to template
##
## Examples:
##   - EPS-Render -template $text
##     will use current context to fill variables in template. If no '$name' exists in current context, it will produce blanks.
##   - EPS-Render -template $text -safe -binding @{ name = "dave" }
##     will use "dave" to render the placeholder "<%= $name %>" in template
##
## Full example:
##   $result = EPS-Render -file $a_file -safe -binding @{ name = "dave" }
##   *Note*: if you use -file parameter, it will omit -template parameter.
##
##   or
##
##   $text = @'
##   Dave is a <% if($true){ %>man<% }else{ %>lady<% } %>.
##   Davie is <%= $age %>.
##   '@
##   
##   $age = 26
##   $result = EPS-Render $text
##
function EPS-Render{
  param(
  [string]$template   = "",
  [string]$file       = "",
  [hashtable]$binding = @{},
  [switch]$safe
  )
  
  if($file -and (test-path $file)){
    $temp1 = gc $file
    $template = $temp1 -join "`n"
  }
  
  if($safe){
    $p = [powershell]::create()
    
    $block = {
      param(
      $temp,
      $libpath,
      $binding = @{}    # variable binding
      )
      
      . $libpath   # load Compile-Raw

      $binding.keys | %{ nv -Name $_ -Value $binding[$_] }     
      
      $script = Compile-Raw $temp      
      $res = iex $script
      write-output $res
    }
    
    [void]$p.addscript($block)
    [void]$p.addparameter("temp",$template)
    [void]$p.addparameter("libpath",$execPath)
    [void]$p.addparameter("binding",$binding)
    $p.invoke()
  }
  else{
    $script = Compile-Raw $template
    iex $script
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
  param(
  [string]$raw,
  [switch]$debug = $false
  )

  #========================
  # constants
  #========================
  $pre_cmd = @('$_temp = ""')
  $post_cmd = @('$_temp')
  $put_cmd = '$_temp += '
  $insert_cmd = '$_temp += ' 
  $p = [regex]'(?si)(?<content>.*?)(?<token><%%|%%>|<%=|<%#|<%|%>|\n)'
  
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
  $pre_cmd | %{ $line += $_ }
  $raw += "`n"
  
  $m = $p.match($raw)
  while($m.success){
    $content = $m.groups["content"].value
    $token = $m.groups["token"].value
    
    if($stag -eq ''){
      
      # escaping characters
      $content = $content -replace '"','`"'
    
      switch($token){
        { $_ -in '<%', '<%=', '<%#'} {
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
              $line += ($insert_cmd + '"' + $content.trim() + '"')
            }
            
            '<%#' { }
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
  
  $post_cmd | %{ $line += $_ }
  $script = ($line -join ';')
  
  if($debug) {
    return $line
  }
  
  $line = $null
  $script
}