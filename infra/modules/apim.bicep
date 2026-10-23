@minLength(1)
@maxLength(50)
param name string
param location string
param tags object
param publisherEmail string
param publisherName string
param skuName string
param skuCapacity int
param logAnalyticsWorkspaceId string
@description('Application Insights component in the same resource group. Empty skips the logger and diagnostic.')
param appInsightsName string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Request metadata only: no bodies are logged.
#disable-next-line use-recent-api-versions
resource logAnalytics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'gateway-logs'
  scope: apim
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
    ]
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!empty(appInsightsName)) {
  name: appInsightsName
}

resource logger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = if (!empty(appInsightsName)) {
  parent: apim
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: appInsights.id
    credentials: {
      instrumentationKey: appInsights!.properties.InstrumentationKey
    }
  }
}

resource diagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = if (!empty(appInsightsName)) {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: logger.id
    // Required by llm-emit-token-metric to send custom metrics to Application Insights.
    metrics: true
    alwaysLog: 'allErrors'
    verbosity: 'information'
    logClientIp: false
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: { body: { bytes: 0 } }
      response: { body: { bytes: 0 } }
    }
    backend: {
      request: { body: { bytes: 0 } }
      response: { body: { bytes: 0 } }
    }
  }
}

output name string = apim.name
output principalId string = apim.identity.principalId
output gatewayUrl string = apim.properties.gatewayUrl
