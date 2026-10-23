using '../main.bicep'

// Rapid innovation (Dev and Sandbox): a shared hub where developers prototype with a model,
// one APIM key per project, low limits so nobody burns the shared quota.
param apimName = 'apim-ai-hub-dev-example'
param publisherEmail = 'platform-team@example.com'
param skuName = 'StandardV2'

param deployMonitoring = true

param deployFoundryAccount = true
param modelName = 'gpt-6-sol'
param modelVersion = '2026-09-22'
param modelCapacity = 15

// One APIM subscription (and key) per project; add a name here to onboard a project.
param apps = ['project-a', 'project-b']
// Per project, per minute. Low on purpose for prototyping; raise it per environment.
param tokensPerMinute = 3000
