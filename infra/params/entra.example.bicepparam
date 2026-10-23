using '../main.bicep'

// Production-style authentication: callers send an Entra ID token instead of a shared key.
// 1. Create the gateway app registration:   infra/entra-setup.sh gateway
// 2. Put its client id below.
// 3. Grant each caller (managed identity object id):   infra/entra-setup.sh grant <client-id> <object-id>
param apimName = 'apim-ai-hub-prod-example'
param publisherEmail = 'platform-team@example.com'
param skuName = 'StandardV2'

param authMode = 'entra'
param entraClientId = '<gateway app registration client id>'
// param entraTenantId = '<tenant id>'          // defaults to the tenant of the deployment
// param entraRequiredRole = 'Gateway.Invoke'   // the app role created by entra-setup.sh

param deployMonitoring = true

param deployFoundryAccount = true
param modelName = 'gpt-6-sol'
param modelVersion = '2026-09-22'
param modelCapacity = 15

// Per calling identity, per minute.
param tokensPerMinute = 10000
