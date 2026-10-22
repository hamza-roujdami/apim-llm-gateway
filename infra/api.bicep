param apimName string
@description('API name; also the gateway URL prefix and the subscription name prefix.')
param name string
param displayName string
@description('Backend base URL. The request path after the API prefix is appended to it.')
param backendUrl string
@allowed(['apiKey', 'managedIdentity'])
param authMode string
param forwardTimeoutSeconds int

var authPolicy = authMode == 'apiKey' ? loadTextContent('policies/api-key.xml') : loadTextContent('policies/managed-identity.xml')
var policy = replace(authPolicy, '__TIMEOUT__', string(forwardTimeoutSeconds))
var operations = loadJsonContent('operations.json')

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
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
  properties: {
    format: 'rawxml'
    value: policy
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

resource subscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: '${name}-default'
  properties: {
    displayName: '${displayName} default'
    scope: api.id
    state: 'active'
  }
}

output subscriptionName string = subscription.name
