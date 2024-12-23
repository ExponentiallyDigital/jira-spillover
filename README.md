# jira-spillover
A tool to report Jira spillover: issues (stories, tasks, bugs) which didn't complete in a sprint.

This is a Windows PowerShell script that returns all Jira issues (_except_ epics and risks) for a user specified project that have been modified within a user defined number of days that have also been worked on in more than one sprint. The results are displayed to the screen and also exported to a user defined tab separated text file for importing and manipulation by Excel or similar tools.

# Why would I care?
Spillover is evil. It represents an inability to complete what was planned within a sprint. Occasional spillover can be justified but rampant and ongoing spillover is a major issue in agile delivery.

# How-to
Do I need to know "programming" to use this tool, no, but you're on your own, it's unsupported and may cause objects in mirrors to be closer than they appear etc. Simply run the tool after you've created a Jira API token, instructions on how to do this are in the jira-spillover.ps1 file.
