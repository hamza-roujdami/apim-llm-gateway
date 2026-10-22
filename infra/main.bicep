targetScope = 'resourceGroup'

metadata description = 'APIM as an AI gateway: a /compass API (api-key) and a /foundry API (managed identity), with an optional Foundry account + model and monitoring.'

// ---------- APIM ----------
@description('APIM instance name (globally unique, 1-50 chars).')
@minLength(1)
@maxLength(50)
param apimName string
param location string = resourceGroup().location
param tags object = {}
param publisherEmail string
param publisherName string = 'LLM Gateway'

@description('Standard v2 is the default: fast to provision, with private endpoint support. Developer is fine for short sandboxes.')
@allowed(['Developer', 'Basic', 'Standard', 'Premium', 'BasicV2', 'StandardV2', 'PremiumV2'])
param skuName string = 'StandardV2'
@minValue(1)
param skuCapacity int = 1

@description('Seconds to wait for backend response headers. Values above 240 may be cut by network idle timeouts on non-streaming calls; prefer stream or background.')
@minValue(1)
param forwardTimeoutSeconds int = 600

// ---------- Gateway protections (apply to both APIs) ----------
@description('Create one APIM subscription per app on each API, named <api>-<app> (for example compass-team-a). Revoke an app by deleting its subscription.')
param apps array = []
@description('Token limit per minute for each subscription (app). 0 = no limit. Over the limit the caller gets 429 with Retry-After.')
@minValue(0)
param tokensPerMinute int = 0
@description('Emit token usage metrics to Application Insights (needs deployMonitoring).')
param emitTokenMetrics bool = true
@description('Retries on a 429 or 503 from the backend. 0 = off.')
@minValue(0)
@maxValue(5)
param retryCount int = 2
@description('Open a circuit breaker after 5 backend 429/5xx errors in a minute, for one minute.')
param enableCircuitBreaker bool = false

// ---------- Monitoring ----------
@description('Create Log Analytics + Application Insights and wire them to APIM.')
param deployMonitoring bool = true

// ---------- Compass ----------
param deployCompassApi bool = true
param compassBackendUrl string = 'https://api.core42.ai'
@description('Models callers may use on /compass. Empty = any model.')
param compassAllowedModels array = []
@secure()
@description('Compass API key. Ignored when compassKeyVaultName is set. Empty deploys a placeholder you replace later.')
param compassApiKey string = ''
@description('Existing Key Vault in this resource group (Azure RBAC authorization) that holds the Compass key. APIM gets "Key Vault Secrets User" on it.')
param compassKeyVaultName string = ''
param compassKeySecretName string = 'compass-api-key'

// ---------- Foundry ----------
param deployFoundryApi bool = true
@description('Models callers may use on /foundry. Empty = any model.')
param foundryAllowedModels array = []
@description('Create a Foundry account, project and model deployment. Set false to use an existing account via foundryAccountName.')
param deployFoundryAccount bool = true
@description('Existing Foundry account in this resource group; used only when deployFoundryAccount is false.')
param foundryAccountName string = ''
param modelDeploymentName string = 'gpt-6-sol'
param modelName string = 'gpt-6-sol'
param modelVersion string = '2026-09-22'
@allowed(['GlobalStandard', 'DataZoneStandard', 'Standard'])
param modelSkuName string = 'DataZoneStandard'
@description('Thousands of tokens per minute. DataZoneStandard needs at least 15.')
@minValue(1)
param modelCapacity int = 15

@description('Also deploy an embeddings model so /foundry/v1/embeddings works.')
param deployEmbeddingModel bool = true
param embeddingModelName string = 'text-embedding-3-large'
@description('Thousands of tokens per minute.')
@minValue(1)
param embeddingCapacity int = 20

var namePrefix = 'llmgw'
var foundryName = deployFoundryAccount ? '${namePrefix}-foundry-${uniqueString(resourceGroup().id)}' : foundryAccountName

module monitoring 'monitoring.bicep' = if (deployMonitoring) {
  name: 'monitoring'
  params: {
    name: namePrefix
    location: location
    tags: tags
  }
}

module foundry 'foundry.bicep' = if (deployFoundryAccount) {
  name: 'foundry'
  params: {
    accountName: foundryName
    projectPrefix: namePrefix
    location: location
    tags: tags
    modelDeploymentName: modelDeploymentName
    modelName: modelName
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
    deployEmbeddingModel: deployEmbeddingModel
    embeddingModelName: embeddingModelName
    embeddingCapacity: embeddingCapacity
  }
}

module apim 'apim.bicep' = {
  name: 'apim'
  params: {
    name: apimName
    location: location
    tags: tags
    publisherEmail: publisherEmail
    publisherName: publisherName
    skuName: skuName
    skuCapacity: skuCapacity
    logAnalyticsWorkspaceId: deployMonitoring ? monitoring!.outputs.logAnalyticsWorkspaceId : ''
    appInsightsId: deployMonitoring ? monitoring!.outputs.appInsightsId : ''
  }
}

var useCompassKeyVault = deployCompassApi && !empty(compassKeyVaultName)

resource compassVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = if (useCompassKeyVault) {
  name: compassKeyVaultName
}

// Key Vault Secrets User
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0e152a9fa2b4')

resource compassVaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useCompassKeyVault) {
  name: guid(compassVault.id, apimName, keyVaultSecretsUserRoleId)
  scope: compassVault
  properties: {
    principalId: apim.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleId
  }
}

module compassKey 'compass-key.bicep' = if (deployCompassApi) {
  name: 'compass-key'
  dependsOn: [compassVaultAccess]
  params: {
    apimName: apim.outputs.name
    apiKey: compassApiKey
    keyVaultSecretUri: useCompassKeyVault ? '${compassVault!.properties.vaultUri}secrets/${compassKeySecretName}' : ''
  }
}

module compassApi 'api.bicep' = if (deployCompassApi) {
  name: 'api-compass'
  dependsOn: [compassKey]
  params: {
    apimName: apim.outputs.name
    name: 'compass'
    displayName: 'Compass'
    backendUrl: compassBackendUrl
    authMode: 'apiKey'
    forwardTimeoutSeconds: forwardTimeoutSeconds
    apps: apps
    tokensPerMinute: tokensPerMinute
    emitTokenMetrics: emitTokenMetrics && deployMonitoring
    retryCount: retryCount
    enableCircuitBreaker: enableCircuitBreaker
    allowedModels: compassAllowedModels
  }
}

module foundryApi 'api.bicep' = if (deployFoundryApi) {
  name: 'api-foundry'
  params: {
    apimName: apim.outputs.name
    name: 'foundry'
    displayName: 'Foundry'
    backendUrl: 'https://${foundryName}.openai.azure.com/openai'
    authMode: 'managedIdentity'
    forwardTimeoutSeconds: forwardTimeoutSeconds
    apps: apps
    tokensPerMinute: tokensPerMinute
    emitTokenMetrics: emitTokenMetrics && deployMonitoring
    retryCount: retryCount
    enableCircuitBreaker: enableCircuitBreaker
    allowedModels: foundryAllowedModels
  }
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = if (deployFoundryApi) {
  name: foundryName
}

// Cognitive Services OpenAI User
var openAiUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')

resource foundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFoundryApi) {
  name: guid(foundryAccount.id, apimName, openAiUserRoleId)
  scope: foundryAccount
  dependsOn: [foundry]
  properties: {
    principalId: apim.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: openAiUserRoleId
  }
}

output gatewayUrl string = apim.outputs.gatewayUrl
output foundryAccountName string = foundryName
output compassSubscriptionName string = deployCompassApi ? compassApi!.outputs.subscriptionName : ''
output foundrySubscriptionName string = deployFoundryApi ? foundryApi!.outputs.subscriptionName : ''
output compassAppSubscriptionNames array = deployCompassApi ? compassApi!.outputs.appSubscriptionNames : []
output foundryAppSubscriptionNames array = deployFoundryApi ? foundryApi!.outputs.appSubscriptionNames : []
