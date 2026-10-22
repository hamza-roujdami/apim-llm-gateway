param apimName string

@secure()
@description('Compass API key. Ignored when keyVaultSecretUri is set. Empty uses a placeholder (Compass answers 401 until it is set).')
param apiKey string

@description('Versionless Key Vault secret URI. APIM reads it with its system identity.')
param keyVaultSecretUri string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource compassKey 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'compass-api-key'
  properties: {
    displayName: 'compass-api-key'
    secret: true
    value: empty(keyVaultSecretUri) ? (empty(apiKey) ? 'set-me-later' : apiKey) : null
    keyVault: empty(keyVaultSecretUri) ? null : {
      secretIdentifier: keyVaultSecretUri
    }
  }
}
