function CacheAnalysis($ResourceGroup,$admin,$pass){

$hostnameurl = (Get-AzWebApp -ResourceGroupName $ResourceGroup | Where-Object {$_.Name -match "-cm"}).DefaultHostName

$Driver = Start-SeFirefox -Quiet -Headless
Enter-SeUrl "https://$($hostnameurl)/sitecore/" -Driver $Driver
Start-Sleep -Second 5
$Username = Find-SeElement -Driver $Driver -Id "Username"
Send-SeKeys -Element $Username -Keys $admin

$Password = Find-SeElement -Driver $Driver -Id "Password"
Send-SeKeys -Element $Password -Keys $pass

$Password.SendKeys([OpenQA.Selenium.Keys]::Enter)
Start-Sleep -Second 10

Enter-SeUrl "https://$($hostnameurl)/sitecore/admin/cache.aspx" -Driver $Driver
for($i=0; $i -lt 4; $i++)
{
$RefreshButton= Find-SeElement -Driver $Driver -ID "c_refresh"
$RefreshButton.Click()
Start-Sleep -Seconds 10
}

Write-host "Start Fetching Cache details" -ForegroundColor Yellow

$cachehtml = $Driver.PageSource
$html = New-Object -ComObject "HTMLFile"
$html.IHTMLDocument2_write($cachehtml)
 
$allvalue =$html.all.tags("td") | % innerText
$output=@()
$a=19
while($a -le $allvalue.Count)
{
    $valueObject = New-Object PSObject
    $valueObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Count" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Size" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Delta" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "MaxSize" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Comment" -Value $allvalue[$a]
    $a++
    $output+= $valueObject
}

$converttohtml = @()
$converttohtml= "<div class='container'><table class='table table-bordered'><tr><td>Name</td><td>Count</td><td>Size</td><td>Max Size</td></tr>"
foreach($val in $output)
{
$recomvalue=""
switch ($val.Name)
{
    "SqlDataProvider - Prefetch data(web)" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"    }
    "web[items]" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"     }
    "AccessResultCache" { $recomvalue = "<br>Recommended value of $($val.Name) is 300 MB"    }
    "web[data]" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"  }
    "SqlDataProvider - Prefetch data(master)" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"   }
    "master[items]" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"     }
    "master[data]" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"   }
    "SqlDataProvider - Prefetch data(core)" { $recomvalue = "<br>Recommended value of $($val.Name) is 500 MB"   }
    "core[data]" { $recomvalue = "<br>Recommended value of $($val.Name) is 500 MB"   }
    "core[items]" { $recomvalue = "<br>Recommended value of $($val.Name) is 500 MB"   }
}



$converttohtml += "<tr><td>$($val.Name)"+ " $($recomvalue)</td><td>$($val.Count)</td><td>$($val.Size)</td><td>$($val.MaxSize)</td></tr>"

}
$converttohtml += "</div>"

Write-host "Created Cache details" -ForegroundColor Yellow
#$converttohtml | Out-File "cache123.html"
return $converttohtml

}

function CacheCDAnalysis($ResourceGroup,$WebAppName){

Upload-CacheConfigtoWebApp $ResourceGroup $WebAppName 
Write-Host "Fetching Cache Details...."
#Start-Sleep -Seconds 6

################################ Create temp folder to download cache files #################

New-Item -Path "C:\Users\asha\Documents\ASHA\Scripts\Security\config\$($ResourceGroup)\temp.zip" -Force

$scriptPath = "C:\Users\asha\Documents\ASHA\Scripts\Security\config\$($ResourceGroup)\temp.zip"


############################ Download Cache file ###############

CheckCache $ResourceGroup $WebAppName $scriptPath
Expand-Archive -LiteralPath $scriptPath -DestinationPath ".\config\$($ResourceGroup)\temp" -Verbose -Force
$cachehtml=Get-ChildItem -Path ".\config\$($ResourceGroup)\temp" -Recurse | group directory | foreach {$_.group | sort LastWriteTime -Descending | select -First 1}
$content= Get-Content -Path ".\config\$($ResourceGroup)\temp\$($cachehtml.Name)" -Raw

$html = New-Object -ComObject "HTMLFile"
$html.IHTMLDocument2_write($content)
 
$allvalue =$html.all.tags("td") | % innerText
#$allvalue
$output=@()
$a=4
while($a -le $allvalue.Count)
{
    $valueObject = New-Object PSObject
    $valueObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Count" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Size" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "MaxSize" -Value $allvalue[$a]
    $a++
    $output+= $valueObject
}
#$output

$converttohtml = @()
$converttohtml= "<div class='container'><table class='table table-bordered'><tr><td>Name</td><td>Count</td><td>Size</td><td>Max Size</td></tr>"
foreach($val in $output)
{

$converttohtml += "<tr><td>$($val.Name)</td><td>$($val.Count)</td><td>$($val.Size)</td><td>$($val.MaxSize)</td></tr>"

}
$converttohtml += "</div>"

Write-host "Created Cache details" -ForegroundColor Yellow
return $converttohtml

}

function Upload-CacheConfigtoWebApp($resourceGroupName, $webAppName, $slotName = "")
{
    $kuduPath= "App_Config/Include/"  
    $ConfigfilePath= "C:\Users\asha\Documents\ASHA\Scripts\Security\cacheconfig.zip"
    $kuduApiAuthorisationToken = Get-KuduApiAuthorisationHeaderValue $resourceGroupName $webAppName $slotName
    if ($slotName -eq ""){
    #https://mywebsite.scm.azurewebsites.net/api/zip/site/wwwroot/subfolder1
        $kuduApiUrl = "https://$webAppName.scm.azurewebsites.net/api/zip/site/wwwroot/$kuduPath"
    }
    else{
        $kuduApiUrl = "https://$webAppName`-$slotName.scm.azurewebsites.net/zip/vfs/site/wwwroot/$kuduPath"
    }
    $virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/zip/site/wwwroot", "")
    Write-Host "Uploading File to WebApp...Source: '$ConfigfilePath'..." -ForegroundColor DarkGray

    Invoke-RestMethod -Uri $kuduApiUrl `
                        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                        -Method PUT `
                        -InFile $ConfigfilePath `
                        -ContentType "multipart/form-data"
}


function Get-AzureRmWebAppPublishingCredentials($resourceGroupName, $webAppName, $slotName = $null){
	if ([string]::IsNullOrWhiteSpace($slotName)){
		$resourceType = "Microsoft.Web/sites/config"
		$resourceName = "$webAppName/publishingcredentials"
	}
	else{
		$resourceType = "Microsoft.Web/sites/slots/config"
		$resourceName = "$webAppName/$slotName/publishingcredentials"
	}
	$publishingCredentials = Invoke-AzResourceAction -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ResourceName $resourceName -Action list -ApiVersion 2015-08-01 -Force
    	return $publishingCredentials
}
function Get-KuduApiAuthorisationHeaderValue($resourceGroupName, $webAppName, $slotName = $null){
    $publishingCredentials = Get-AzureRmWebAppPublishingCredentials $resourceGroupName $webAppName $slotName
    return ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $publishingCredentials.Properties.PublishingUserName, $publishingCredentials.Properties.PublishingPassword))))
}
function Download-FileFromWebApp($resourceGroupName, $webAppName, $slotName = "", $kuduPath, $localPath){

    $kuduApiAuthorisationToken = Get-KuduApiAuthorisationHeaderValue $resourceGroupName $webAppName $slotName
    if ($slotName -eq ""){
    #https://mywebsite.scm.azurewebsites.net/api/zip/site/wwwroot/subfolder1
        $kuduApiUrl = "https://$webAppName.scm.azurewebsites.net/api/zip/site/wwwroot/$kuduPath"
    }
    else{
        $kuduApiUrl = "https://$webAppName`-$slotName.scm.azurewebsites.net/zip/vfs/site/wwwroot/$kuduPath"
    }
    $virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/zip/site/wwwroot", "")
    Write-Host " Downloading File from WebApp. Source: '$virtualPath'. Target: '$localPath'..." -ForegroundColor DarkGray

    Invoke-RestMethod -Uri $kuduApiUrl `
                        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                        -Method GET `
                        -OutFile $localPath `
                        -ContentType "multipart/form-data"
}

function CheckCache($resourceGroupName, $webAppName, $scriptPath){
   
    $kuduPath = "App_Data/diagnostics/health_monitor/"
    $localPath = "$scriptPath"
    $addedGetSitecoreVersionIpRestrictionRule = $false

    Try
    {        
        Download-FileFromWebApp $resourceGroupName $webAppName "" $kuduPath $localPath

        if (!(Test-Path -Path $localPath)){
            Update-AzureIpRestrictionRule -ResourceGroupName $resourceGroupName -AppServiceName $webAppName -Action Add
            $addedGetSitecoreVersionIpRestrictionRule = $true

            $retry = 3
            do {                
                Download-FileFromWebApp $resourceGroupName $webAppName "" $kuduPath $localPath

                if (!(Test-Path -Path $localPath)){                
                    Write-Host "Retrying in 5 seconds...($retry)" -ForegroundColor DarkGray
                    Start-Sleep -s 5
                    $retry = $retry - 1                                
                }
                else {
                    $retry = 0
                }
            }
            While ($retry -gt 0)

            if (!(Test-Path -Path $localPath)){                
                    return $null
            }
        }
        
    }    
    Catch
    {
        return $null
    }
    
}
