@description('Account name; also the custom subdomain (globally unique).')
param accountName string
@description('Prefix for the project name.')
param projectPrefix string
param location string
param tags object

@description('Model deployment name; clients use it as the model name.')
param modelDeploymentName string
param modelName string
param modelVersion string
@allowed(['GlobalStandard', 'DataZoneStandard', 'Standard'])
param modelSkuName string
@description('Thousands of tokens per minute. DataZoneStandard needs at least 15.')
@minValue(1)
param modelCapacity int

@description('Also deploy an embeddings model.')
param deployEmbeddingModel bool
@description('Embeddings deployment name (same as the model name).')
param embeddingModelName string
@description('Thousands of tokens per minute.')
@minValue(1)
param embeddingCapacity int
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
  name: modelDeploymentName
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

// One write at a time on the account: deploy after the chat model.
resource embedding 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployEmbeddingModel) {
  parent: account
  name: embeddingModelName
  dependsOn: [model]
  sku: {
    name: modelSkuName
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: '1'
    }
  }
}
