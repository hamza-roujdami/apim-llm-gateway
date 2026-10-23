@description('Account name; also the custom subdomain (globally unique).')
param accountName string
@description('Prefix for the project name.')
param projectPrefix string
param location string
param tags object
@description('Turn off API keys on the account so APIM (Entra identity) is the only way in.')
param disableLocalAuth bool

@description('Model name. The deployment is named after it, and clients send that name as "model".')
param modelName string
param modelVersion string
@allowed(['GlobalStandard', 'DataZoneStandard', 'Standard'])
param modelSkuName string
@description('Thousands of tokens per minute. DataZoneStandard needs at least 15.')
@minValue(1)
param modelCapacity int

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: accountName
    allowProjectManagement: true
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: disableLocalAuth
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: '${projectPrefix}-project'
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    displayName: 'LLM Gateway project'
  }
}

// The account allows one write operation at a time, so deploy the model after the project.
resource model 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: modelName
  dependsOn: [project]
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}
