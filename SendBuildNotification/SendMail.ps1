[CmdletBinding()]
param(
[Parameter(Mandatory=$False)]
[string] $send = "",
[Parameter(Mandatory=$True)]
[string] $To,
[Parameter(Mandatory=$False)]
[string] $Subject = "",
[Parameter(Mandatory=$True)]
[string] $From,
[Parameter(Mandatory=$False)]
[string] $AddAttachment = "True",
[Parameter(Mandatory=$False)]
[string] $Attachment,
[Parameter(Mandatory=$True)]
[string] $TestPlan,
[Parameter(Mandatory=$True)]
[string] $VSOUsername,
[Parameter(Mandatory=$True)]
[string] $VSOUserPAT,
[Parameter(Mandatory=$False)]
[string] $OrgVersion = "",
[Parameter(Mandatory=$False)]
[string] $Message = ""
)

$MailParams = @{}
Write-Output "Entering script SendMail.ps1"
Write-Output "Input Variables ##"
Write-Output "Send Email To: $To"
Write-Output "Subject: $Subject"
Write-Output "Send Email From: $From"
Write-Output "Add Attachment?: $AddAttachment"
Write-Output "Attachment: $Attachment"

function GetGitAuthHeaders($VSOUsername, $VSOUserPAT)
{
   if (! [String]::IsNullOrWhiteSpace($VSOUserPAT))
    {
        $token=$VSOUserPAT; # RO access token to pull-requests and basic user profile info
        $basicAuth=("{0}:{1}" -f $VSOUsername,$token)
        $basicAuth=[System.Text.Encoding]::UTF8.GetBytes($basicAuth)
        $basicAuth=[System.Convert]::ToBase64String($basicAuth)
        $headers = @{Authorization=("Basic {0}" -f $basicAuth)}
    }
    else
    {
        Write-Error "A token must be provided. Either VSOUserPAT or SYSTEM_ACCESSTOKEN must be defined."
        Exit 1
    }
    return $headers
}

function GetEmailContent([scriptblock]$modifier)
{
    #Get Email Content from Template
    $mailContent = Get-Content "$PSSCriptRoot\BuildEmail.html" -Raw

    if($modifier)
    {
        $mailContent = $modifier.Invoke($mailContent)
    }
    return $mailContent
} 


try
{
$projectURL = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID"
Write-Output "Project URL: $projectURL"

$buildId= if( $Env:BUILD_BUILDID -ne  $null) {$Env:BUILD_BUILDID} else {"The script is run not from build"}
Write-Output "Build ID: $buildId"

$buildNumber= if( $Env:BUILD_BUILDNUMBER -ne  $null) {$Env:BUILD_BUILDNUMBER} else {"The script is run not from build"}
Write-Output "Build Number: $buildNumber"

$buildURI= if( $Env:BUILD_BUILDURI -ne  $null) {$Env:BUILD_BUILDURI} else {"The script is run not from build"}
Write-Output "Build URI: $buildURI"

$buildRepositoryName = if( $Env:BUILD_REPOSITORY_NAME -ne  $null) {$Env:BUILD_REPOSITORY_NAME} else {"The script is run not from build"}
Write-Output "Build Repository Name: $buildRepositoryName"

$commitId = if( $Env:BUILD_SOURCEVERSION -ne  $null) {$Env:BUILD_SOURCEVERSION} else {"The script is run not from build"}
Write-Output "Build Commit Id: $commitId"


# Get the header for Build APIs
$headers = GetGitAuthHeaders $VSOUsername $VSOUserPAT

$buildURL = "$projectURL/_apis/build/builds/$buildId"
Write-Output "Build URL: $buildURL"
$build = Invoke-RestMethod -Uri $buildURL  -Headers $headers -Method "GET"
$buildCreatedBy = $build.requestedFor.uniqueName
$buildId = $build.id


#Process the build timeline
$url = "$projectURL/_apis/build/builds/$buildId/timeline"
Write-Output "Build Timeline URL: $url"

Do
{
  $buildTimeline = Invoke-RestMethod -Uri $url -Headers $headers -Method "GET"
  $n = $buildTimeline.records.Count
  $s = $buildTimeline.records.Where({$_.state -eq "completed" }).Count  
  $f = $buildTimeline.records.Where({$_.result -eq "failed" }).Count
  Write-Output "Total Tasks: $n    Completed Tasks: $s    Failed Tasks: $f"  
 # $output = "Total Tasks:$n  Completed Tasks:$s  Failed Tasks:$f" 
  $output = ""
  foreach ($record in $buildTimeline.records) 
  {
    if($record.result -eq "failed" -and $record.errorCount -gt 0)
    {
       $output = $output + "<b>$($record.name): Failed.</b><br/>"
        
        foreach ($issue in $record.issues) {
            if($issue.type -eq "error")
            {
                $output = $output + "$($issue.message)"
            }
        }
    }
  }
  
  if($f -gt 0) {break}
  # There are always 2 tasks "inProgress" state in timeline of the build: "Send email if build is failed" task and Build task
} While ($s -lt ($n-2))

if($f -eq 0) 
{
    $buildStatus = "Succeeded"
    $Subject = "$buildRepositoryName Build $buildNumber - Succeeded"
}
else
{
    $buildStatus = "Rejected"
    $Subject = "$buildRepositoryName Build $buildNumber - Rejected"
}

#### TEST RUN INFORMATION ####
#Test Run Info
$url = "$projectURL/_apis/test/runs/?api-version=3.0-preview&planId=$TestPlan"
Write-Output "Test Run URL: $url"
$testRuns = Invoke-RestMethod -Uri $url -Headers $headers -Method Get

if($testRuns.count -gt 0)
{
    $testRunsIdSorted = $testRuns.value | sort-object id -Descending
    $testRunId = $($testRunsIdSorted[0].id)
    Write-Output "Test Run ID: $($testRunsIdSorted[0].id)" 
    Write-Output "Test Run Name: $($testRunsIdSorted[0].name)" 
    Write-Output "Test Run State: $($testRunsIdSorted[0].state)" 
    
    #Test Result
    $url = "$projectURL/_apis/test/runs/$($testRunsIdSorted[0].id)/results?api-version=3.0-preview&planId=$TestPlan"
    Write-Output "Test Result URL: $url"
    $testResults = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    $testResultsIdSorted = $testResults.value | sort-object id -Descending
    Write-Output "Test Result ID: $($testResultsIdSorted[0].id)"

    $url = "$projectURL/_apis/test/runs/$($testRunsIdSorted[0].id)/results"
    $testResult = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    Write-Output "Test Result Count: $($testResult.count)"
    
    $testResultHtml = '<h4>Please find below the details of the test run</h4><table cellspacing="0" cellpadding="2"><tbody>'
    $testResultHtml = $testResultHtml + '<tr>'
    $testResultHtml = $testResultHtml + '<th style="width:100px;" valign="top"><b>ID</b></th>'
    $testResultHtml = $testResultHtml + '<th style="width:100px;" valign="top"><b>Test Name</b></th>'
    $testResultHtml = $testResultHtml + '<th style="width:120px;" valign="top"><b>Test State</b></th>'
    $testResultHtml = $testResultHtml + '<th style="width:150px;" valign="top"><b>Test Status</b></th>'
    $testResultHtml = $testResultHtml + '<th valign="top"><b>Error Details</b></th>'
    $testResultHtml = $testResultHtml + '</tr>'
  
    foreach ($testCase in $testResult.value) 
    {
        $tc = $testCase.testCase 
        $testResultHtml = $testResultHtml + '<tr>'
        $testResultHtml = $testResultHtml + "<td valign=top>$($tc.id)</td>"
        $testResultHtml = $testResultHtml + "<td valign=top>$($tc.name)</td>"
     
        if($($testCase.state) -eq "Pending")
        {
            $testResultHtml = $testResultHtml + "<td valign='top' class='pending'>$($testCase.state)</td>"
        }
        else
        {
             $testResultHtml = $testResultHtml + "<td valign=top>$($testCase.state)</td>"         
        }
     
        if($($testCase.outcome) -eq "Failed")
        {
            $testResultHtml = $testResultHtml + "<td valign='top' class='error'>$($testCase.outcome)</td>"
        }
        else
        {
            $testResultHtml = $testResultHtml + "<td valign='top' class='passed'>$($testCase.outcome)</td>"
        }
        $testResultHtml = $testResultHtml + "<td valign='top' class='error'>$($testCase.errorMessage)<br><br>$($testCase.stackTrace)</td>"
        $testResultHtml = $testResultHtml + '</tr>'        
    }
    $testResultHtml = $testResultHtml + "</tbody></table>"

     
    $testResultHtml = $testResultHtml + '<br/><br/><a href="#TEST_RUN_URL#">Click here</a> to view the Test Run Summary.'
    
    
    #Test Attachments
    $url = "$projectURL/_apis/test/runs/$testRunId/attachments?api-version=3.0-preview&planId=$TestPlan"
    Write-Output "Test Attachment URL: $url"
    $testAttachments = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    if($testAttachments.count -gt 0)
    {
        $testAttachmentsIdSorted = $testAttachments.value | sort-object id -Descending
        Write-Output "Test Attachment: $($testAttachmentsIdSorted[0].filename)"
        Write-Output "Test Attachment ID: $($testAttachmentsIdSorted[0].id)"
        Write-Output "Test Attachment URL: $($testAttachmentsIdSorted[0].url)"
        $testAttachmentURL = $($testAttachmentsIdSorted[0].url)
        $testResultHtml = $testResultHtml + '<br/><a href="$testAttachmentURL">Click here</a> to DOWNLOAD the TRX File of test run.'          
    }
    
}

$modifier = {
              param($content)
                $content=$content -replace "#BUILD_ID#", $buildId
                $content=$content -replace "#BUILD_NUMBER#", $buildNumber
                $content=$content -replace "#BUILD_URL#", "$projectURL/_build?_a=summary&buildId=$buildId" 
                
                if($buildStatus -eq "Rejected")
                {
		            $content=$content -replace "#BUILD_STATUS#",  "<span class='error'>$buildStatus</span>"
                }
                else
                {
                    $content=$content -replace "#BUILD_STATUS#",  $buildStatus
                }
                $content=$content -replace "#REPOSITORY#",  $buildRepositoryName                
				$content=$content -replace "#ORG_VERSION#",  $OrgVersion
				$content=$content -replace "#CREATED_BY#", $buildCreatedBy
                $content=$content -replace "#COMMIT_ID#", $commitId
                $content=$content -replace "#TEST_RESULT_HTML#", $testResultHtml 
                $content=$content -replace "#ADDITIONAL_MESSAGE#", $Message                
                $content=$content -replace "#TEST_RUN_URL#", "$projectURL/_testManagement/runs?_a=runCharts&runId=$testRunId" 
                $content=$content -replace "#TEST_ATTACHMENT_URL#", "$projectURL/_testManagement/runs?_a=runCharts&runId=$testRunId" 
                if($output -ne "")
                {
                    $output = "<br/><div class='error'>$output<br/></div>"
                }
                $content=$content -replace "#OUTPUT#", $output
                
               
                return $content
            }.GetNewClosure()
            
$Body = GetEmailContent $modifier                  

#[string[]]$ToMailAddresses=$To.Split(';');
[bool]$BodyAsHtmlBool = [System.Convert]::ToBoolean($BodyAsHtml)
[bool]$AddAttachmentBool =  [System.Convert]::ToBoolean($AddAttachment)

$tempFile=[System.IO.Path]::GetTempFileName()+".htm";
$Subjectxpanded = $ExecutionContext.InvokeCommand.ExpandString($Subject) 
$BodyExpanded = $ExecutionContext.InvokeCommand.ExpandString($Body) 


    if($Attachment -is [System.Collections.ArrayList]){
        $Attachment = $Attachment -join ","
        write-Output $Attachment
    }

    if($BodyExpanded)
    {
        $BodyExpanded | Out-File $tempFile
        if ($Attachment -ne $null) {
            &"$PSSCriptRoot\smartmail.exe" smtp verbose:full server:smtphost auth:sspi from:$From to:$To "body:$tempFile" content-type:text/html "Subject:$Subjectxpanded" attach:"$Attachment"
        } else {
            &"$PSSCriptRoot\smartmail.exe" smtp verbose:full server:smtphost auth:sspi from:$From to:$To "body:$tempFile" content-type:text/html "Subject:$Subjectxpanded"
        }
        
    }
    else
    {
        Write-Warning "Mail body must not be empty"
    }
}
catch
{
    Write-Output "Error=" $_.Exception.Message ";Script=SendMail.ps1"
    throw
}
Write-Output "Leaving script SendMail.ps1"