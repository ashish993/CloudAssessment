param
(
    [Parameter(Mandatory = $true)] [string]$ResourceGroup,
    [Parameter(Mandatory = $true)] [string]$subscriptionId,
    [Parameter(Mandatory = $true)] [string]$TenantId,
    [Parameter(Mandatory = $true)] [string]$AppId,
    [Parameter(Mandatory = $true)] [string]$AppSecret,
    [Parameter(Mandatory = $true)] [string]$sqluser,
    [Parameter(Mandatory = $true)] [string]$sqlpass
)
Import-Module "$PSScriptRoot\CacheAnalysis.psm1" -Force -Verbose

# ----------------- Login as a Service Pricipal  -----------------
$secret = ConvertTo-SecureString $AppSecret -AsPlainText -Force
$Cred = New-Object System.Management.Automation.PSCredential($AppId, $secret)
Add-AzAccount -Credential $Cred -TenantId $TenantId -ServicePrincipal

Set-AzContext -Subscription $subscriptionId
$WarningPreference = "SilentlyContinue"
$ErrorPreference = "SilentlyContinue"

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
        $kuduApiUrl = "https://$webAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kuduPath"
    }
    else{
        $kuduApiUrl = "https://$webAppName`-$slotName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kuduPath"
    }
    $virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/vfs/site/wwwroot", "")
    Write-Host " Downloading File from WebApp. Source: '$virtualPath'. Target: '$localPath'..." -ForegroundColor DarkGray

    Invoke-RestMethod -Uri $kuduApiUrl `
                        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                        -Method GET `
                        -OutFile $localPath `
                        -ContentType "multipart/form-data"
}

function ChechFcnAppInti($SubscriptionId, $resourceGroupName, $webAppName, $scriptPath){
   $fcnappinitvalue =@()
    $subscriptionSelected = $SubscriptionId
    $kuduPath = "Web.config"
    # $kuduPath = "sitecore/shell/sitecore.version.xml"
    $localPath = "$scriptPath\Web.config"
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
    

    [xml]$XmlDocument = Get-Content -Path $localPath

    if ($XmlDocument.SelectSingleNode('//httpRuntime').HasAttribute('fcnMode') -eq $true){
        [STRING]$fcnMode=$XmlDocument.SelectSingleNode('//httpRuntime').GetAttribute('fcnMode') 
        if ($fcnMode -eq 'Disabled') { #if tehre is fcnMode but it is disabled
             $fcnappinitvalue+= "No recommendations for fcnMode for ASP.Net."
             Write-Host "No recommendations for fcnMode for ASP.Net."
        }
        else
        {
             $fcnappinitvalue+= "Disable fcnMode for ASP.Net."
           Write-Host  "Disable fcnMode for ASP.Net."
        }
        #Maybe Should add else statement here as well
    }
    else{
    Write-Host "Do not find FcnMode configuration."
         $fcnappinitvalue+= "Do not find FcnMode configuration."
    }
    
    Remove-Item $localPath
    # [STRING]$fcnMode=$XmlDocument.SelectSingleNode('//httpRuntime').GetAttribute('fcnMode') #Prefetch. Needs to be 1000MB (currently cannot find)
    if ($XmlDocument.SelectSingleNode('//applicationInitialization') -ne $null){
        [STRING]$appInt=$XmlDocument.SelectSingleNode('//applicationInitialization').GetAttribute('doAppInitAfterRestart') 
        if ($appInt -eq 'false') { #if there is app init in web config but it is false
            $fcnappinitvalue+= "There is app initialisation but it is false."
        }
         else{
             $fcnappinitvalue+=  "No recommendations for app initialisation."
         }
    }
    else{
         $fcnappinitvalue+= "Enable Asp.Net Application Initialization feature"
    }

    return $fcnappinitvalue
}

function CheckCache($SubscriptionId, $resourceGroupName, $webAppName, $scriptPath){
   $checkcache= @()
    $subscriptionSelected = $SubscriptionId
    $kuduPath = "App_Config/Sitecore.config"
    # $kuduPath = "sitecore/shell/sitecore.version.xml"
    $localPath = "$scriptPath\\Sitecore.config"
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
        [xml]$XmlDocument = Get-Content -Path $localPath


    #Remove-Item $localPath
    [STRING]$Prefetch=$XmlDocument.SelectSingleNode('//setting[@name="Caching.DefaultDataCacheSize"]').Value #Prefetch. Needs to be 1000MB (currently cannot find)
    [STRING]$Data=$XmlDocument.SelectSingleNode('//setting[@name="Caching.DefaultDataCacheSize"]').Value #Data. Needs to be 1000MB
    [STRING]$Item =$XmlDocument.SelectSingleNode('//setting[@name="Caching.DefaultItemPathsCacheSize"]').Value #Item. Needs to be 1000MB
    [STRING]$HTML=$XmlDocument.SelectSingleNode('//setting[@name="Caching.DefaultHtmlCacheSize"]').Value #HTML. Needs to be 1000MB
    [STRING]$AccessResultCache=$XmlDocument.SelectSingleNode('//setting[@name="Caching.AccessResultCacheSize"]').Value #AccessResultCache. Needs to be 1000MB

    [int]$PrefetchInt=[int]$Prefetch.Replace("MB","")
    [int]$DataInt=[int]$Data.Replace("MB","")
    [int]$ItemInt=[int]$Item.Replace("MB","")
    [int]$HTMLInt=[int]$HTML.Replace("MB","")
    [int]$AccessResultCacheInt=$AccessResultCache.Replace("MB","")

    $RecommendedPrefetchValue=1000
    $RecommendedDataValue=1000
    $RecommendedItemValue=1000
    $RecommendedHTMLValue=200
    $RecommendedAccessResultValue=200

    if ($PrefetchInt -lt $RecommendedPrefetchValue) {
        $checkcache+= "Recommended Value for Prefetch Cache is $($RecommendedPrefetchValue) MB"
        $checkcache+= "Current Value is $($Prefetch)"
    }
    if ($DataInt -lt $RecommendedDataValue) {
        $checkcache+= "Recommended Value for Data Cache is $($RecommendedDataValue) MB"
        $checkcache+= "Current Value is  $($Data)"
    }
    if ($ItemInt -lt $RecommendedItemValue) {
        $checkcache+= "Recommended Value for Item Cache is $($RecommendedItemValue) MB"
        $checkcache+= "Current Value is $($Item)"
    }
    if ($HTMLInt -lt $RecommendedHTMLValue) {
        $checkcache+= "Recommended Value for HTML Cache is $($RecommendedHTMLValue) MB"
        $checkcache+= "Current Value is $($HTML)"
    }
    if ($AccessResultCacheInt -lt $RecommendedAccessResultValue) {
        $checkcache+= "Recommended Value for AccessResult Cache is $($RecommendedAccessResultValue)MB"
        $checkcache+= "Current Value is $($AccessResultCache)"
    }

    return $checkcache
    }    
    Catch
    {
        return $null
    }
    
}


$FinalOutput =@()
$wafresult = @()

$FinalOutput= "<html><head> <title>Sitecore MCS Recommendations</title> <meta charset='utf-8'> <meta name='viewport' content='width=device-width, initial-scale=1'> <link rel='stylesheet' href='https://maxcdn.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css'> <script src='https://ajax.googleapis.com/ajax/libs/jquery/3.5.1/jquery.min.js'></script> <script src='https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.16.0/umd/popper.min.js'></script> <script src='https://maxcdn.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js'></script> </head> <div class='jumbotron text-center'> <h1>Recommendations for Sitecore MCS Azure Resources</h1> <p>This report will contains details of our best practices and recommendations for ensuring that your Sitecore environment is as secure as possible. It is important to remember that secure software is a goal that we are constantly trying to achieve but may never reach. If you need any assistance for this report, please raise a new support ticket on Sitecore support portal.</p> </div><div class='container'>"
######### Check Application Gateway is provisioned or not ############
Write-Host "Checking Recommendations for WAF" -ForegroundColor Yellow
$wafdetails= Get-AzApplicationGateway -ResourceGroupName $ResourceGroup

if($wafdetails -ne $null)
{
$wafresult = "Application Gateway is provisioned in the subscription. <br>"
######### Check Firewall Mode ############

$firewallmode= $wafdetails.WebApplicationFirewallConfiguration.FirewallMode
if($firewallmode -eq "Prevention")
{
$wafresult += "WAF mode is Prevention<br>"
######### Check Disabled Rules ############
$ruledetails = $wafdetails.WebApplicationFirewallConfiguration.DisabledRuleGroups.Rules
if ($ruledetails -gt 0)
{
$wafresult += "$($ruledetails.Count) Rules are disabled. Disabling any rule groups or rules may expose you to increased security risks. <br>"
}
else
{
$wafresult += "No rules are disabled. <br>"
}
}
else
{
$wafresult += "Highly recommended to change WAF mode to Prevention to secure your Sitecore Environment.<br>"
}
}
else
{
$wafresult= "Highly recommended to provision Application Gateway WAF to secure your Sitecore Environment.<br>"
}
$FinalOutput += "<h1> Recommendations for WAF </h1><p> $($wafresult) </p>"

################################# Check Web App ####################################
$FinalOutput += "<h1> Recommendations for Azure WebApps </h1>"
$webappdetails = Get-AzWebApp -ResourceGroupName $ResourceGroup

foreach($webapp in $webappdetails)
{
$webappresult = @()
Write-Host "Checking Recommendations for $($webapp.Name)" -ForegroundColor Yellow
$config =Get-AzWebapp -ResourceGroupName $ResourceGroup -Name $webapp.Name
if($config.SiteConfig.NetFrameworkVersion -ne "v4.0")
{
    $webappresult += "Ensure that App Service .Net Stack settings should be latest.<br>"
}

if($config.SiteConfig.MinTlsVersion -ne "1.2")
{
    $webappresult += "Use the latest version of TLS encryption<br>"
}
if ($config.SiteConfig.FtpsState -eq "AllAllowed")
{
    $webappresult += "Disable FTP deployments<br>"
}
if ($config.SiteConfig.Http20Enabled -ne "True")
{
    $webappresult += "HTTP version should be latest<br>"
}
if ($config.HttpsOnly -eq "False")
{
    $webappresult += "Redirect HTTP traffic to HTTPS<br>"
}

foreach ($siteconfig in $config.SiteConfig.AppSettings) 
{
    if($siteconfig.Name -eq "WEBSITE_DYNAMIC_CACHE" -and $siteconfig.Value -ne 0)
    {
        $webappresult += "Disable Dynamic Cache<br>"
    }
}

if($config.SiteConfig.AppSettings.Name.Contains("WEBSITE_LOCAL_CACHE_OPTION"))
    {
        $webappresult += "<br>"
    }
    else
    {
        $webappresult += "Enable Azure local cache feature.<br>"
    }



#Checking App Service Plan

$appserviceplan=Get-AzAppServicePlan -ResourceGroupName $ResourceGroup -Name $($webapp.ServerFarmId.Split('/\')[-1])
if ($appserviceplan.Sku -eq "Basic")
{
   $webappresult += "Using the Basic App Service plan is not recommended.<br>"
}
# 
$backupconfig= Get-AzWebAppBackupList -ResourceGroupName $ResourceGroup -Name $webapp.Name | Sort-Object Created -Descending
if($backupconfig -eq $null)
{
$webappresult += "Backup Configuration not found.<br>"
}
else
{
if($backupconfig.BackupStatus[0] -eq "Failed")
{
$webappresult += "Backup Failed for $($webapp.Name) <br>"
}

}

#Checking Scaling Info

$cputimeavg=0
$t=0
$met =Get-AzMetric -ResourceId $webapp.Id -MetricName "CpuTime" -StartTime ((Get-Date).AddDays(-7)) -WarningAction SilentlyContinue
$avgdata = $met.Data | Select-Object Average

foreach($avg in $avgdata)
{
    $t += $avg.Average
}
$cputimeavg= $dtu/($avgdata).Count

if($cputimeavg -gt 85)
{
$webappresult += "Review the performance plan of $($webapp.Name).<br>"
}
else
{
if($cputimeavg -lt 15)
{
$webappresult += "Scale down the performance plan of $($webapp.Name). <br>"
}

$FinalOutput += "<p><b>Recommendations for Azure WebApp $($webapp.Name)</b><br> $($webappresult) <br></p>"
}

}

#Check CM IP restriction rules
$ipRestrictionwafresult = @()
#Get CM instance
$cminstance= Get-AzWebApp -ResourceGroupName $ResourceGroup | Where-Object {$_.Name -match "-cm"}
$cmRestriction =Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $ResourceGroup -Name $cminstance.Name

foreach($restriction in $cmrestriction.MainSiteAccessRestrictions)
{
    if($restriction.RuleName -eq "Allow all")
    {
        $ipRestrictionwafresult = "<b>Consider IP restrictions for CM and Application Insights IP ranges for ping checks</b>"
    }
    
}

$FinalOutput += "<p>$ipRestrictionwafresult</p>"

################################# Check Azure SQL ####################################
$sqlserverresult = @()
$sqlserver =Get-AzSqlServer -ResourceGroupName $ResourceGroup
$sqldb = Get-AzSqlDatabase -ServerName $sqlserver.ServerName -ResourceGroupName $ResourceGroup

############################ Setting Firewall in SQL Server ############################

$ruleName = "$env:USERNAME-SitecoreAuditing"

$client = New-Object System.Net.WebClient
[xml]$response = $client.DownloadString("http://checkip.dyndns.org")
$ip = ($response.html.body -split ':')[1].Trim()
New-AzSqlServerFirewallRule -ServerName $sqlserver.ServerName -ResourceGroupName $resourceGroup -FirewallRuleName $ruleName -StartIpAddress $ip -EndIpAddress $ip

######## SQL Server ########
Write-Host "Checking Recommendations for Azure SQL Server" -ForegroundColor Yellow
$FinalOutput += "<h1> Recommendations for Azure SQL Server </h1><p>"

$sqlauditdetails=Get-AzSqlServerAudit -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName
if($sqlauditdetails.BlobStorageTargetState -ne "Enabled" -and $sqlauditdetails.EventHubTargetState -ne "Enabled" -and $sqlauditdetails.EventHubTargetState -ne "Enabled")
{
    $sqlserverresult += "Enable auditing on SQL Server $($sqlserver.ServerName) <br>"
}

$sqlthreatdetection=Get-AzSqlServerAdvancedThreatProtectionSetting -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName
if($sqlthreatdetection.ThreatDetectionState -eq "Disabled")
{
    $sqlserverresult += "Enable Threat Detection on SQL Server <br>"
}


$sqladmin= Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName
if($sqladmin -eq $null)
{
$sqlserverresult += "Use Azure Active Directory Authentication for authentication with SQL Server. <br>"
}
$FinalOutput += "<b>Recommendations for Azure SQL Server $($sqlserver.ServerName) </b><br> $($sqlserverresult)"

######## SQL Database ########
Write-Host "Checking Recommendations for Azure Databases" -ForegroundColor Yellow

$FinalOutput += "</p><h1> Recommendations for Azure SQL Database </h1><p>"

foreach($db in $sqldb)
{
$sqlresult=@()

$dbauditdetails=Get-AzSqlDatabaseAudit -ResourceGroupName $ResourceGroup -DatabaseName $db.DatabaseName -ServerName $sqlserver.ServerName
if($auditdetails.BlobStorageTargetState -ne "Enabled" -and $auditdetails.EventHubTargetState -ne "Enabled" -and $auditdetails.EventHubTargetState -ne "Enabled")
{
    $sqlresult += "Enable auditing on $($db.DatabaseName).<br>"
}

$dbthreatdetection=Get-AzSqlDatabaseAdvancedThreatProtectionSetting -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName -DatabaseName $db.DatabaseName
if($dbthreatdetection.ThreatDetectionState -eq "Disabled")
{
    $sqlresult += "Enable Threat Detection on $($db.DatabaseName).<br>"
}
$dbencryption = Get-AzSqlDatabaseTransparentDataEncryption -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName -DatabaseName $db.DatabaseName
if($dbencryption.State -ne "Enabled")
{
    $sqlresult += "Enable Data Encryption on $($db.DatabaseName).<br>"
}


$sqlquery = "SELECT top 1 DB_NAME() AS DBName ,OBJECT_NAME(ps.object_id) AS TableName ,i.name AS IndexName ,ips.index_type_desc ,ips.avg_fragmentation_in_percent ,ps.row_count FROM sys.dm_db_partition_stats ps INNER JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id CROSS APPLY sys.dm_db_index_physical_stats(DB_ID(), ps.object_id, ps.index_id, null, 'LIMITED') ips ORDER BY ips.avg_fragmentation_in_percent DESC"
$dbfragmentation = Invoke-Sqlcmd -ServerInstance $($sqlserver.ServerName+('.database.windows.net')) -Database $db.DatabaseName -Query $sqlquery -Username $sqluser -Password $sqlpass -Verbose
if($dbfragmentation.avg_fragmentation_in_percent -gt '80')
{
    $sqlresult += "Enable Azure SQL maintenance plan for index fragmentation on $($db.DatabaseName).<br>"
}

#Checking SQL Scaling Info

$sqlcputimeavg=0

$dtumetric =Get-AzMetric -ResourceId $db.ResourceId -MetricName "dtu_consumption_percent" -StartTime ((Get-Date).AddDays(-7)) -WarningAction SilentlyContinue
$dtudata = $dtumetric.Data | Select-Object Average
$dtu=0
foreach($avg in $dtudata)
{
    $dtu += $avg.Average
}
$sqlcputimeavg= $dtu/($dtudata).Count

if($sqlcputimeavg -gt 85)
{
$sqlresult += "Review the performance plan of $($db.DatabaseName).<br>"
}
if($sqlcputimeavg -lt 15)
{
$sqlresult += "Scale down the performance plan of $($db.DatabaseName). <br>"
}


$FinalOutput += "<b>Recommendations for Azure SQL Database $($db.DatabaseName) </b><br> $($sqlresult) <br>"
}
############################ Remove Firewall in SQL Server ############################

Remove-AzSqlServerFirewallRule -FirewallRuleName $ruleName -ServerName $sqlserver.ServerName -ResourceGroupName $ResourceGroup -Force

################################# Check Azure CDN ####################################
Write-Host "Checking Recommendations for Azure CDN" -ForegroundColor Yellow
$cdn=Get-AzCdnProfile
if($cdn -ne $null)
{
$cdnendpoint =Get-AzCdnEndpoint -ProfileName $cdn.Name -ResourceGroupName $ResourceGroup
if($cdnendpoint -eq $null)
{
$FinalOutput += "<b>Recommendations for Azure CDN</b><br><p>No CDN found. Use Azure CDN to cache Sitecore Media Library.</p>"
}
else
{
$FinalOutput += "<b>Recommendations for Azure CDN</b><br><p>No Recommendations for Azure CDN .</p>"
}
}
else
{
$FinalOutput += "<b>Recommendations for Azure CDN</b><br><p>No CDN found. Use Azure CDN to cache Sitecore Media Library.</p>"
}

############################### Check Search Service ##################################
$search =Get-AzResource -ResourceGroupName $ResourceGroup -ResourceType Microsoft.Search/searchServices
if($search.Count -gt 0)
{
$FinalOutput += "<b>Recommendations for Search Service</b><br><p>Use Solr Search instead of Azure Search Service.</p>"
}
else
{
$FinalOutput += "<b>Recommendations for Search Service</b><br><p>No Recommendations for Search Service.</p>"
}

############################### Check Cache tuning , Application Initialization & fcnMode ##################################
$FinalOutput += "<b>Recommendations for Cache Tuning, Application Initialization & Asp.Net FcnMode</b><br/></p>"
$webappCD = Get-AzWebApp -ResourceGroupName $ResourceGroup | Where-Object {$_.Name -match "-cd"}
$webappCM = Get-AzWebApp -ResourceGroupName $ResourceGroup | Where-Object {$_.Name -match "-cm"}
$tempPath = $PSScriptRoot+"/config"

$FinalOutput +=ChechFcnAppInti $subscriptionId $ResourceGroup $webappCD.Name $tempPath
$FinalOutput +=ChechFcnAppInti $subscriptionId $ResourceGroup $webappCM.Name $tempPath
$FinalOutput +=CheckCache $subscriptionId $ResourceGroup $webappCD.Name $tempPath
$FinalOutput +=CheckCache $subscriptionId $ResourceGroup $webappCM.Name $tempPath

$FinalOutput += "</div>"
$FinalOutput |  Out-File -FilePath .\Report.html
