param apimName string
param backendUrl string
@description('How callers authenticate: an APIM subscription key, or an Entra ID token checked with validate-jwt.')
@allowed(['subscriptionKey', 'entra'])
param authMode string
@description('Key mode only: one APIM subscription per app, named foundry-<app>, in addition to foundry-default.')
param apps array
@description('Entra mode: tenant that issues the tokens.')
param entraTenantId string
@description('Entra mode: client ID of the gateway app registration (the token audience).')
param entraClientId string
@description('Entra mode: app role a token must carry.')
param entraRequiredRole string
@description('Token limit per subscription (app) per minute. 0 turns the limit off.')
param tokensPerMinute int
@description('Emit per-app token usage metrics to Application Insights. Needs the APIM Application Insights diagnostic.')
param emitTokenMetrics bool

var apiName = 'foundry'
var operations = loadJsonContent('responses-operations.json')

var isEntra = authMode == 'entra'

// Entra mode counts per caller identity (the client app id in the token); key mode counts per APIM subscription.
var counterKey = isEntra ? '@((string)context.Variables["caller"])' : '@(context.Subscription.Id)'
var callerAuthXml = isEntra
  ? replace(replace(replace(loadTextContent('policies/entra-auth.xml'), '__TENANT_ID__', entraTenantId), '__CLIENT_ID__', entraClientId), '__ROLE__', entraRequiredRole)
  : ''
var tokenLimitXml = tokensPerMinute > 0
  ? '<llm-token-limit counter-key="${counterKey}" tokens-per-minute="${tokensPerMinute}" estimate-prompt-tokens="false" remaining-tokens-header-name="x-remaining-tokens" retry-after-header-name="Retry-After" />'
  : ''
var tokenMetricDimension = isEntra ? '<dimension name="Caller" value="@((string)context.Variables["caller"])" />' : '<dimension name="Subscription ID" />'
var tokenMetricXml = emitTokenMetrics
  ? '<llm-emit-token-metric namespace="llm-gateway">${tokenMetricDimension}<dimension name="API ID" /></llm-emit-token-metric>'
  : ''
var policyXml = replace(replace(replace(loadTextContent('policies/llm-api-policy.xml'), '__CALLER_AUTH__', callerAuthXml), '__TOKEN_LIMIT__', tokenLimitXml), '__TOKEN_METRIC__', tokenMetricXml)

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: apiName
  properties: {
    displayName: 'Foundry'
    path: apiName
    protocols: ['https']
    serviceUrl: backendUrl
    // Key mode: clients send the APIM subscription key in the "api-key" header. Entra mode: validate-jwt is the gate.
    subscriptionRequired: !isEntra
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'subscription-key'
    }
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: policyXml
  }
}

resource apiOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for op in operations: {
  parent: api
  name: op.name
  properties: {
    displayName: op.displayName
    method: op.method
    urlTemplate: op.urlTemplate
    templateParameters: [for p in op.templateParameters: {
      name: p
      type: 'string'
      required: true
    }]
  }
}]

resource defaultSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = if (!isEntra) {
  parent: apim
  name: '${apiName}-default'
  properties: {
    displayName: 'Foundry default'
    scope: api.id
    state: 'active'
  }
}

resource appSubscriptions 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = [for app in apps: if (!isEntra) {
  parent: apim
  name: '${apiName}-${app}'
  properties: {
    displayName: 'Foundry ${app}'
    scope: api.id
    state: 'active'
  }
}]

output subscriptionName string = isEntra ? '' : '${apiName}-default'
var appSubscriptionNames = [for app in apps: '${apiName}-${app}']
output appSubscriptionNames array = isEntra ? [] : appSubscriptionNames
