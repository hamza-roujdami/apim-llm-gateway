targetScope = 'resourceGroup'

metadata description = 'APIM as an AI gateway for Microsoft Foundry: the Responses API for gpt-6-sol, with optional monitoring.'

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

// ---------- Caller authentication ----------
@description('subscriptionKey: each app gets an APIM subscription key (simple, good for dev and sandbox). entra: callers send an Entra ID token with the gateway app role (recommended for production); needs entraClientId.')
@allowed(['subscriptionKey', 'entra'])
param authMode string = 'subscriptionKey'

@description('Key mode: create one APIM subscription per app, named foundry-<app> (for example foundry-team-a). Revoke an app by deleting its subscription. Ignored in entra mode.')
param apps array = []

@description('Entra mode: client ID of the gateway app registration, which is the audience of the tokens. Create it with infra/entra-setup.sh.')
param entraClientId string = ''
@description('Entra mode: tenant that issues the tokens.')
param entraTenantId string = tenant().tenantId
@description('Entra mode: app role that a token must carry. Grant it to each caller with infra/entra-setup.sh.')
param entraRequiredRole string = 'Gateway.Invoke'

@description('Token limit per app per minute (per APIM subscription in key mode, per calling identity in entra mode). Keep it at or below the model capacity. 0 turns the limit off.')
@minValue(0)
param tokensPerMinute int = 10000

// ---------- Monitoring ----------
@description('Create Log Analytics + Application Insights and wire them to APIM.')
param deployMonitoring bool = true

// ---------- Foundry ----------
@description('Create a Foundry account, project and the model deployment. Set false to use an existing account via foundryAccountName; it must already have the model deployed under the name in modelName.')
param deployFoundryAccount bool = true
@description('Existing Foundry account in this resource group; used only when deployFoundryAccount is false.')
param foundryAccountName string = ''
@description('Model name. The deployment is named after it, and clients send that name as "model".')
param modelName string = 'gpt-6-sol'
param modelVersion string = '2026-09-22'
@allowed(['GlobalStandard', 'DataZoneStandard', 'Standard'])
param modelSkuName string = 'DataZoneStandard'
@description('Thousands of tokens per minute. DataZoneStandard needs at least 15.')
@minValue(1)
param modelCapacity int = 15
@description('Turn off API keys on the Foundry account, so APIM (Entra identity) is the only way in. Applies when the account is created here.')
param disableFoundryLocalAuth bool = true

var namePrefix = 'llmgw'
var foundryName = deployFoundryAccount ? '${namePrefix}-foundry-${uniqueString(resourceGroup().id)}' : foundryAccountName

module monitoring 'modules/monitoring.bicep' = if (deployMonitoring) {
  name: 'monitoring'
  params: {
    name: namePrefix
    location: location
    tags: tags
  }
}

module foundry 'modules/foundry.bicep' = if (deployFoundryAccount) {
  name: 'foundry'
  params: {
    accountName: foundryName
    projectPrefix: namePrefix
    location: location
    tags: tags
    modelName: modelName
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
    disableLocalAuth: disableFoundryLocalAuth
  }
}

module apim 'modules/apim.bicep' = {
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
    appInsightsName: deployMonitoring ? monitoring!.outputs.appInsightsName : ''
  }
}

module api 'modules/api.bicep' = {
  name: 'api'
  params: {
    apimName: apim.outputs.name
    backendUrl: 'https://${foundryName}.openai.azure.com/openai'
    authMode: authMode
    apps: apps
    entraTenantId: entraTenantId
    entraClientId: entraClientId
    entraRequiredRole: entraRequiredRole
    tokensPerMinute: tokensPerMinute
    emitTokenMetrics: deployMonitoring
  }
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryName
}

// Cognitive Services OpenAI User
var openAiUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')

resource foundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
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
output subscriptionName string = api.outputs.subscriptionName
output appSubscriptionNames array = api.outputs.appSubscriptionNames
