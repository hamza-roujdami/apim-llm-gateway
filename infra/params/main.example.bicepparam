using '../main.bicep'

param apimName = 'apim-llm-gateway-example'
param publisherEmail = 'admin@example.com'
param skuName = 'StandardV2'

// Log Analytics + Application Insights
param deployMonitoring = true

// Compass: leave the key empty to deploy now and set it later.
param deployCompassApi = true
param compassBackendUrl = 'https://api.core42.ai'
// Or keep the key in an existing Key Vault (Azure RBAC, reachable by APIM). The secret name defaults to compass-api-key.
// param compassKeyVaultName = '<vault-name>'
// param compassAllowedModels = ['gpt-6-sol', 'text-embedding-3-large']

// Per-app access and protections (apply to both APIs)
// param apps = ['team-a', 'team-b']      // one subscription per app and API, e.g. compass-team-a
// param tokensPerMinute = 5000          // per app; 0 = no limit
// param retryCount = 2                  // retries on 429 (and 503 without the circuit breaker); 0 = off
// param enableCircuitBreaker = true
// param emitTokenMetrics = true         // needs deployMonitoring

// Foundry: create an account + project + model, or use an existing account in this resource group.
param deployFoundryApi = true
// param foundryAllowedModels = ['gpt-6-sol', 'text-embedding-3-large']
param deployFoundryAccount = true
// param deployFoundryAccount = false
// param foundryAccountName = '<existing-account-name>'
param modelDeploymentName = 'gpt-6-sol'
param modelName = 'gpt-6-sol'
param modelVersion = '2026-09-22'
param deployEmbeddingModel = true
param embeddingModelName = 'text-embedding-3-large'
