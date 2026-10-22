using '../main.bicep'

param apimName = 'apim-llm-gateway-example'
param publisherEmail = 'admin@example.com'
param skuName = 'StandardV2'

// Log Analytics + Application Insights
param deployMonitoring = true

// Compass: leave the key empty to deploy now and set it later.
param deployCompassApi = true
param compassBackendUrl = 'https://api.core42.ai'

// Foundry: create an account + project + model, or use an existing account in this resource group.
param deployFoundryApi = true
param deployFoundryAccount = true
// param deployFoundryAccount = false
// param foundryAccountName = '<existing-account-name>'
param modelDeploymentName = 'gpt-6-sol'
param modelName = 'gpt-6-sol'
param modelVersion = '2026-09-22'
param deployEmbeddingModel = true
param embeddingModelName = 'text-embedding-3-large'
