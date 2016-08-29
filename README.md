[![Build status](https://ci.appveyor.com/api/projects/status/dkkgi7fg8fsubqph?svg=true)](https://ci.appveyor.com/project/dbroeglin/eps)

EPS
===
EPS ( *Embedded PowerShell* ), inspired by erb, is a templating tool that renders PowerShell code into text document, conceptually and syntactically similar to erb for Ruby or twig for PHP, etc.    

>EPS is uploaded to [PowerShellGallary](https://www.powershellgallery.com/packages/EPS/0.2.0).
And (if the gallary works well) You can install the module with command:
```
PS> Install-Module -Name EPS 
```

### Syntax
EPS allows PowerShell code to be embedded within a pair of `<% ... %>`, `<%= ... %>`, or `<%# ... %>` as well:

- Code in `<% ... %>` blocks are treated as statements or commands
- Code in `<%= ... %>` blocks are treated as values or expressions   
- Text in `<%# ... %>` blocks are treated as comment which will be ignored in compilation    

> 
You can write multiple-line commands in a ```<% ... %>``` block.
You can also write code which produce text output in `<% ... %>` blocks, instead of using a `<%= ... %>` block.
But in this style the output text is not produced **in-place** for sure    

### Commandline usage

```
Expand-Template [[-template] $inline_template_str] | [-file $template_file] [-safe -binding $params_hash]
```   
   

- use **-template** to provide template text via a commandline param rather than a file
- if **-file** exists, it ignores **-template** param and render the template content in the file   
- **-safe** renders template in **isolated** mode (in another thread/powershell space) to avoid variable pollution (variable name already in current context)    
- if **-safe** is provided, you should bind your values using **-binding** option with a hashtable containing k-v pairs   

### Example

In a template file 'test.eps':   

```
Hi <%= $name %>

<%# this is a comment %>
Please buy me the following items:
<% 1..5 | %{ %>
  - <%= $_ %> pigs ...
<% } %>

Dave is a <% if($true) { %> boy <% } else { %> girl <% } %>. 

Thanks,
Dave
<%= (Get-Date -f yyyy-MM-dd) %>
```

Then render it in commandline:
```powershell
. .\eps.ps1  # load this tool into current PowerShell space

$name = "ABC"
Expand-Template -file test.eps
```

>  
Here it is in non-safe mode (render template with values in current run space)
To use safe mode: using `Expand-Template -file test.eps -safe` with binding values
   

It will produce:   

```
Hi ABC

Please buy me the following items:
  - 1 pigs ...
  - 2 pigs ...
  - 3 pigs ...
  - 4 pigs ...
  - 5 pigs ...

Dave is a boy.

Thanks,
Dave
2014-06-09
```

Or you can use safe mode with data bindings:
```powershell
Expand-Template -file $file_name -safe -binding @{ name = "dave" }
```
which will generate same output.

### More examples
any statement result in a `<% ... %>` block will be placed at the template top (that's why you should use `<%= ... %>` instead):   

```powershell
$template = @'
Hi, dave is a <% if($true) { "boy" } else { "girl" } %>
'@

Expand-Template -template $template
```
will produce:   

```
boy
Hi, dave is a 
```

for another instance, if template is
```
Hi dave
Don't watch TV.

Your wife
<% get-date -f yyyy-MM-dd %>
```
It will produce:   

```
2014-06-10
Hi dave
Don't watch TV.

Your wife
```   

> You should use `<%= ... %>` instead, since `<%= $(get-date -f yyyy-MM-dd) %>` produces the date string at the same place.

   
You can use multi-line statements in `<% ... %>` block:   
```powershell
$template = @'

<%
  $name = "dave"
  
  1..5 | %{
    "haha"
  }
%>

Hello, I'm <%= $name %>.
'@

Expand-Template -template $template
```

it will produce:   
```
haha
haha
haha
haha
haha

Hello, I'm dave.
```

> Reminder: the output of statements in `<% ... %>` block will be put at top, not in-place 


## Contribution

* Original version was written by [Dave Wu](https://github.com/straightdave).
* Maintained now and extended by [Dominique Broeglin (@dbroeglin)](https://github.com/dbroeglin), thank you pal 谢谢！

Help find more bugs! Or find more usage of this tool ...
Author's email: eyaswoo@163.com
