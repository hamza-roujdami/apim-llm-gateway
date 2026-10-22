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

// ---------- Monitoring ----------
@description('Create Log Analytics + Application Insights and wire them to APIM.')
param deployMonitoring bool = true

// ---------- Compass ----------
param deployCompassApi bool = true
param compassBackendUrl string = 'https://api.core42.ai'
@secure()
@description('Compass API key. Empty deploys a placeholder you replace later.')
param compassApiKey string = ''

// ---------- Foundry ----------
param deployFoundryApi bool = true
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
    compassApiKey: compassApiKey
    createCompassKey: deployCompassApi
  }
}

module compassApi 'api.bicep' = if (deployCompassApi) {
  name: 'api-compass'
  params: {
    apimName: apim.outputs.name
    name: 'compass'
    displayName: 'Compass'
    backendUrl: compassBackendUrl
    authMode: 'apiKey'
    forwardTimeoutSeconds: forwardTimeoutSeconds
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
