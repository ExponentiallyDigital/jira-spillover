#################################################################################################################################
# get-spillover.ps1
#
# Author: Andrew Newbury, December 2024
#
# Purpose: Returns Jira issues (except epics and risks) for the user specified project that have been modified within a user
#          defined number of days that have also been worked on in more than one sprint. Displays results to screen and exports
#          to tab separated text file for importing and manipulation by Excel or similar tools.
#
# Input: 1. Requires a text file called "Jira-API-token.txt" in the current directory, the file must contain only 1 line, for example
#             "your-atlassian-account-email-address:128-random-numbers-and-characters"
#           Create an API token via https://id.atlassian.com/manage-profile/security/api-tokens
#           For detailed iinstructions see https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/      
#           Secure the API token file, via powershell:
#                icacls Jira-API-token.txt /inheritance:r /grant:r "$($env:USERNAME):(R)"
#             the Windows command line:
#                icacls Jira-API-token.txt /inheritance:r /grant:r "%USERNAME%:(R)"
#             or with Linux via:
#                chmod 400 Jira-API-token.txt && chown $(whoami) Jira-API-token.text
#        2. Set $jiraBaseUrl to your Jira instance, for Jira cloud this is typically https://my-org-name.atlassian.net"
#
# History:
#           2.04 set up for Atlassian cloud
#           2.03 removed auth token from script, reads from a local file in the current directory
#           2.02 include status in returned data
#           2.00 check issue resolved date falls within the prior days to check (avoid records updated due to Confluence links being edited etc)
#           1.10 optimised: batch epic title lookup, two pass processing, reduced API calls, hashtables for lookups
#           1.00 initial private release
#
#################################################################################################################################
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# For the purposes of attribution please use https://www.linkedin.com/in/andrewnewbury
#################################################################################################################################
#
# Jira URL for your organisation
$jiraBaseUrl = "https://my-org-name.atlassian.net"

#################################################################################################################################
# Function to fetch issues
function Get-JiraIssues {
    param (
        [string]$Jql,
        [int]$StartAt = 0,
        [int]$MaxResults = 100
    )

    $EncodedJql = [uri]::EscapeDataString($Jql)
    $Url = "$JiraBaseUrl/rest/api/2/search?jql=$EncodedJql&startAt=$StartAt&maxResults=$MaxResults&fields=key,summary,status,issuetype,customfield_14181,customfield_10002,customfield_14182,assignee,resolutiondate&expand=changelog"
    Write-Output "Fetching Issues URL: $Url"
    $Response = Invoke-RestMethod -Uri $Url -Headers $Headers -Method Get
    return $Response
}

#################################################################################################################################
# Function to batch lookup Epic Titles
function Get-EpicTitles {
    param (
        [string[]]$EpicKeys
    )

    # Remove duplicates and filter out empty or "No Epic"
    $UniqueEpicKeys = $EpicKeys | Where-Object { 
        -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne "No Epic" 
    } | Select-Object -Unique

    $EpicTitles = @{}

    foreach ($EpicKey in $UniqueEpicKeys) {
        try {
            Write-Host "." -NoNewline # Progress dot for each epic lookup
            $EpicUrl = "$JiraBaseUrl/rest/api/2/issue/$EpicKey"
            $EpicResponse = Invoke-RestMethod -Uri $EpicUrl -Headers $Headers -Method Get

            $EpicTitle = $EpicResponse.fields."customfield_14183"
            $EpicTitles[$EpicKey] = if ([string]::IsNullOrEmpty($EpicTitle)) { "No Epic Title" } else { $EpicTitle }
        } catch {
            $EpicTitles[$EpicKey] = "Epic Title Lookup Failed"
        }
    }
    return $EpicTitles
}

#################################################################################################################################
# Main Program Execution
#
# Steps:
# 1. Read the Jira API token used for secure Jira access
# 2. Prompt the user for required inputs (e.g., Jira project ID, number of days to check, output filename)
# 3. Build the JQL query based on user input and retrieve matching Jira issues
# 4. Filter issues based on the number of sprints they have worked in
# 5. Look up the associated Epic titles and gather additional details
# 6. Format the output and display it to the user
# 7. Save the results to a file
#
# Inputs:
# - Jira project ID
# - Number of days to check for updated issues
# - Output filename for saving results
#
# Outputs:
# - List of issues worked on in more than one sprint, including details like issue type, status, and Epic title.
# - Results saved to the specified output file (or default file if none provided).
##############################################################################################################

# read API token from file
$TokenFile = ".\Jira-API-token.txt"
$JiraApiToken = Get-Content -Path $TokenFile -Raw
if (Test-Path $TokenFile) {
    $JiraApiToken = Get-Content -Path $TokenFile -Raw
} else {
    Write-Output "Error: Jira API token file not found"
    exit 1
}

# Prompt for project ID and number of days prior
$ProjectKey = Read-Host "`nEnter the Jira Project ID (e.g., AWSF)"
$DaysPrior = Read-Host "Enter the number of days prior to check for updated issues (default is 10)"
# Convert to integer, defaulting to 10 if not a valid number
if (-not [int]::TryParse($DaysPrior, [ref]$DaysPrior)) {
    $DaysPrior = 10
}

# Prompt for output filename
$OutputFileName = Read-Host "Enter the filename to save the results (default *overwrites* issues_output.txt)"

# Use default filename if user input is empty
if ([string]::IsNullOrWhiteSpace($OutputFileName)) {
    $OutputFileName = "issues_output.txt"
}

# Ensure the filename has a .txt extension
if (-not $OutputFileName.EndsWith('.txt')) {
    $OutputFileName += '.txt'
}

# JQL query to return specific records for x number of user-specified days
$JqlQuery = "project = $ProjectKey AND issuetype not in (Epic, Risk) AND updated >= -$DaysPrior" + "d"

# Base64 encode the authentication
$Base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$JiraApiToken"))

# Define headers
$Headers = @{
    "Authorization" = "Basic $Base64Auth"
    "Accept"        = "application/json"
}

# Fetch all issues matching the JQL
$Issues = @()
$StartAt = 0
$MaxResults = 100
do {
    $Response = Get-JiraIssues -Jql $JqlQuery -StartAt $StartAt -MaxResults $MaxResults
    Write-Output "Fetched $($Response.issues.Count) issues, StartAt=$StartAt, Total=$($Response.total)"
    $Issues += $Response.issues
    $StartAt += $MaxResults
} while ($StartAt -lt $Response.total)

# initialise storage arrays: jira record data, epic links for each jira record
$MultisprintIssues = @()
$EpicLinksToLookup = @()

# Loop through each issue in the $Issues collection
foreach ($Issue in $Issues) {
    # Calculate days since resolved
    $ResolvedDate = $null
    if ($Issue.fields.resolutiondate) {
        $ResolvedDate = [datetime]::Parse($Issue.fields.resolutiondate)
        $DaysSinceResolved = (New-TimeSpan -Start $ResolvedDate -End (Get-Date)).Days

        # Skip issues resolved more than the specified days ago, this is useful if an old issue was updated due to say a Confluence link being changed
        if ($DaysSinceResolved -gt $DaysPrior) {
            continue # Skip this issue and move to the next iteration if resolved too long ago
        }
    }

    # Count the number of sprints from the customfield_14181 array (unique sprint entries)
    $WorkedSprints = @()
    if ($Issue.fields."customfield_14181") {
        foreach ($Sprint in $Issue.fields."customfield_14181") {
            $SprintName = $Sprint -replace '^.*name=', '' -replace ',.*$', ''
            if ($SprintName -notin $WorkedSprints) {
                $WorkedSprints += $SprintName # Add the sprint name to the array if not already present
            }
        }
    }

    # Count the total number of sprints from the changelog
    $TotalSprints = 0
    foreach ($History in $Issue.changelog.histories) {
        foreach ($Item in $History.items) {
            if ($Item.field -eq "Sprint") {
                $TotalSprints++ # Increment the sprint count based on the changelog history
            }
        }
    }

    # Check if the issue has more than one worked sprint AND more than one sprint in the history
    if ($WorkedSprints.Count -gt 1 -and $TotalSprints -gt 1) {
        # Prepare the issue for further processing
        $EpicLink = $Issue.fields."customfield_14182"
        if (-not $EpicLink) {
            $EpicLink = "No Epic"
        }

        # Add the issue to the list of multi-sprint issues with relevant data
        $MultisprintIssues += @{
            Issue = $Issue
            WorkedSprints = $WorkedSprints.Count
            TotalSprints = $TotalSprints
            EpicLink = $EpicLink
            ResolvedDate = $ResolvedDate
        }

        # Collect unique epic links to lookup later
        if ($Issue.fields."customfield_14182") {
            $EpicLinksToLookup += $Issue.fields."customfield_14182"
        }
    }
}

# Batch lookup of Epic Titles
$EpicTitles = Get-EpicTitles -EpicKeys $EpicLinksToLookup

# Prepare final output
$FilteredIssues = @()

foreach ($IssueData in $MultisprintIssues) {
    Write-Host "." -NoNewline # show a progress dot for each issue being processed (useful for large data sets to show that the script is still working)
    $Issue = $IssueData.Issue
    
    # Get issue status
    $Status = $Issue.fields.status.name
    if (-not $Status) { $Status = "Unknown" }

    # Get story points (customfield_10002)
    $StoryPoints = $Issue.fields."customfield_10002"
    if (-not $StoryPoints) { $StoryPoints = "N/A" }

    # Get assignee
    $Assignee = $Issue.fields.assignee
    if ($null -eq $Assignee) { $Assignee = "Unassigned" } else { $Assignee = $Assignee.displayName }

    # Get Epic Title
    $EpicTitle = $EpicTitles[$IssueData.EpicLink]
    if (-not $EpicTitle) {
        $EpicTitle = "No Epic Title"
    }

    # Get Issue Type
    $IssueType = $Issue.fields.issuetype.name
    if (-not $IssueType) { $IssueType = "Unknown" }

    # Format the output
    $FormattedOutput = "$($IssueData.WorkedSprints)`t$($IssueData.TotalSprints)`t$IssueType`t$($Issue.key)`t$($Issue.fields.summary)`t$Status`t$($IssueData.EpicLink)`t$EpicTitle`t$StoryPoints`t$Assignee"
    $FilteredIssues += $FormattedOutput
}

# Prepare the header line
$HeaderLine = "worked sprints`ttotal sprints`tissue key`tissue summary`tepic key`tepic summary`tstory points`tassignee"

# Display results to stdout
if ($FilteredIssues.Count -eq 0) {
    Write-Output "No issues found matching the criteria."
} else {
    Write-Output "`nFound $($FilteredIssues.Count) issues in more than one sprint:`n"
    Write-Output $HeaderLine
    $FilteredIssues | ForEach-Object { Write-Output $_ }
}

# Save results to file
try {
    # Create the file with the header line
    $HeaderLine | Out-File -FilePath $OutputFileName -Encoding UTF8

    # Append the filtered issues
    $FilteredIssues | Out-File -FilePath $OutputFileName -Encoding UTF8 -Append

    Write-Output "`nResults saved to $OutputFileName"
} catch {
    Write-Output "Error saving file: $_"
}
