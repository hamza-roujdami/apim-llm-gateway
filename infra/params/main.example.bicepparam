using '../main.bicep'

param apimName = 'apim-llm-gateway-example'
param publisherEmail = 'admin@example.com'
param skuName = 'StandardV2'

// Log Analytics + Application Insights
param deployMonitoring = true

// Foundry: create an account + project + gpt-6-sol, or use an existing account in this resource group
// (it must already have gpt-6-sol deployed under that name).
param deployFoundryAccount = true
// param deployFoundryAccount = false
// param foundryAccountName = '<existing-account-name>'
param modelName = 'gpt-6-sol'
param modelVersion = '2026-09-22'

// Per-app access: one APIM subscription (and key) per app
// param apps = ['team-a', 'team-b']                            // creates foundry-team-a and foundry-team-b
// param tokensPerMinute = 10000                                // per app; keep at or below the model capacity; 0 = no limit
