param apimName string
@description('API name; also the gateway URL prefix and the subscription name prefix.')
param name string
param displayName string
@description('Backend base URL. The request path after the API prefix is appended to it.')
param backendUrl string
@allowed(['apiKey', 'managedIdentity'])
param authMode string
param forwardTimeoutSeconds int

@description('One APIM subscription per app, named <api>-<app>, in addition to <api>-default.')
param apps array = []
@description('Token limit per minute for each subscription (app). 0 = no limit.')
@minValue(0)
param tokensPerMinute int = 0
@description('Emit token usage metrics to Application Insights, per API and subscription.')
param emitTokenMetrics bool = false
@description('Retries on a 429 or 503 from the backend (not on streams already started). 0 = off.')
@minValue(0)
@maxValue(5)
param retryCount int = 0
@description('Trip a circuit breaker after repeated backend 429/5xx errors (needs a backend resource).')
param enableCircuitBreaker bool = false
@description('Allowed model names for chat, embeddings and responses requests. Empty = any model.')
param allowedModels array = []

var authPolicy = authMode == 'apiKey' ? loadTextContent('policies/api-key.xml') : loadTextContent('policies/managed-identity.xml')
var operations = loadJsonContent('operations.json')
var backendId = '${name}-backend'

var setBackend = enableCircuitBreaker ? '<set-backend-service backend-id="${backendId}" />' : ''
var tokenLimit = tokensPerMinute > 0 ? '<llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="${tokensPerMinute}" estimate-prompt-tokens="false" />' : ''
var tokenMetric = emitTokenMetrics ? '<llm-emit-token-metric namespace="llm-gateway"><dimension name="API ID" /><dimension name="Subscription ID" /></llm-emit-token-metric>' : ''
var forwardAttributes = 'timeout="${forwardTimeoutSeconds}" buffer-response="false" fail-on-error-status-code="false"'
// With the circuit breaker on, 503 is not retried so an open breaker answers immediately.
var retryOn503 = enableCircuitBreaker ? '' : ' || context.Response.StatusCode == 503'
var forwardRequest = retryCount > 0 ? '<retry condition="@(context.Response != null && (context.Response.StatusCode == 429${retryOn503}))" count="${retryCount}" interval="1" delta="2" first-fast-retry="false"><forward-request ${forwardAttributes} buffer-request-body="true" /></retry>' : '<forward-request ${forwardAttributes} />'
var apiPolicyXml = replace(replace(authPolicy, '__INBOUND_EXTRAS__', '${setBackend}${tokenLimit}${tokenMetric}'), '__FORWARD__', forwardRequest)

var allowedModelsList = join(map(allowedModels, model => '"${model}"'), ', ')
var modelPolicyXml = replace(loadTextContent('policies/model-allowlist.xml'), '__ALLOWED_MODELS__', allowedModelsList)

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource backend 'Microsoft.ApiManagement/service/backends@2024-05-01' = if (enableCircuitBreaker) {
  parent: apim
  name: backendId
  properties: {
    url: backendUrl
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          name: 'trip-on-backend-errors'
          failureCondition: {
            count: 5
            interval: 'PT1M'
            statusCodeRanges: [
              { min: 429, max: 429 }
              { min: 500, max: 599 }
            ]
          }
          tripDuration: 'PT1M'
          acceptRetryAfter: true
        }
      ]
    }
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: name
  properties: {
    displayName: displayName
    path: name
    protocols: ['https']
    serviceUrl: backendUrl
    subscriptionRequired: true
    // Clients send the APIM subscription key in "api-key"; the policy replaces it before the backend call.
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'subscription-key'
    }
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  dependsOn: [backend]
  properties: {
    format: 'rawxml'
    value: apiPolicyXml
  }
}

resource apiOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for op in operations: {
  parent: api
  name: op.name
  properties: {
    displayName: op.name
    method: op.method
    urlTemplate: op.urlTemplate
    templateParameters: [for p in op.templateParameters: {
      name: p
      type: 'string'
      required: true
    }]
  }
}]

resource modelPolicies 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = [for (op, i) in operations: if (!empty(allowedModels) && op.modelInBody) {
  parent: apiOperations[i]
  name: 'policy'
  dependsOn: [apiPolicy]
  properties: {
    format: 'rawxml'
    value: modelPolicyXml
  }
}]

resource defaultSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: '${name}-default'
  properties: {
    displayName: '${displayName} default'
    scope: api.id
    state: 'active'
  }
}

resource appSubscriptions 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = [for app in apps: {
  parent: apim
  name: '${name}-${app}'
  properties: {
    displayName: '${displayName} ${app}'
    scope: api.id
    state: 'active'
  }
}]

output subscriptionName string = defaultSubscription.name
output appSubscriptionNames array = [for (app, i) in apps: appSubscriptions[i].name]
