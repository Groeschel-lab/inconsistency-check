// Inconsistency Check - subscription-scoped, keyless one-click deployment.
// Azure Functions (Elastic Premium) hosting the logic-check app; keyless
// Managed-Identity + RBAC to the model and storage; storage behind Private
// Endpoints. Supports the Claude Opus 4.7 reference model (Anthropic route)
// and the study's other models, plus optional end-user Entra authentication.
targetScope = 'subscription'

@description('Azure region (EU). Claude Opus 4.7 (the paper reference model) is only in swedencentral.')
@allowed([ 'swedencentral', 'germanywestcentral', 'switzerlandnorth' ])
param location string = 'swedencentral'

@description('Short unique suffix for resource names (3-8 lowercase letters/digits, e.g. logic1).')
@minLength(3)
@maxLength(8)
param nameSuffix string

@description('Which of the paper\'s five models to deploy. Claude Opus 4.7 is the validation reference.')
@allowed([ 'claude-opus-4-7', 'gpt-5.5', 'mistral-large-3', 'deepseek-v3.2', 'gpt-5.4-nano' ])
param modelProfile string = 'claude-opus-4-7'

@description('Requested model capacity (thousands of tokens/min); clamped to a safe per-model maximum.')
@minValue(1)
@maxValue(500)
param modelCapacity int = 20

@description('Organization name for Anthropic (Claude) model provider data (marketplace requirement for Claude).')
param organizationName string = 'Healthcare organization'

@description('ISO 3166 alpha-2 country code for Anthropic model provider data.')
param countryCode string = 'DE'

@description('Industry for Anthropic model provider data.')
param industry string = 'Healthcare'

@description('Optional. Override the built-in v4_judge system prompt. Empty = paper default.')
param systemPrompt string = ''

@description('Optional. Entra app registration (client) ID to require user sign-in. Empty = no user auth. Create the app registration yourself - see README.')
param entraClientId string = ''

@description('Entra tenant ID for sign-in. Defaults to the deployment tenant.')
param entraTenantId string = tenant().tenantId

@description('Application package (zip). Defaults to the latest GitHub release build.')
param packageUri string = 'https://github.com/helloworld-germany/inconsistency-check/releases/latest/download/app.zip'

@description('Resource group to create/use.')
param resourceGroupName string = 'rg-logiccheck-${nameSuffix}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module core 'modules/core.bicep' = {
  scope: rg
  name: 'core-${nameSuffix}'
  params: {
    location: location
    nameSuffix: nameSuffix
    modelProfile: modelProfile
    modelCapacity: modelCapacity
    organizationName: organizationName
    countryCode: countryCode
    industry: industry
    systemPrompt: systemPrompt
    packageUri: packageUri
    entraClientId: entraClientId
    entraTenantId: entraTenantId
  }
}

output functionAppUrl string = core.outputs.functionAppUrl
output foundryEndpoint string = core.outputs.foundryEndpoint
output modelDeployment string = core.outputs.modelDeployment
output modelLabel string = core.outputs.modelLabel
output authIdentityClientId string = core.outputs.authIdentityClientId
output authIdentityPrincipalId string = core.outputs.authIdentityPrincipalId
output authFederationIssuer string = core.outputs.authFederationIssuer
