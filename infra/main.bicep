// Subscription-scoped deployment for the Function App and model infrastructure.
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

@description('Organization name for the model provider data.')
param organizationName string = 'Healthcare organization'

@description('ISO 3166 alpha-2 country code for the model provider data.')
param countryCode string = 'DE'

@description('Industry for the model provider data.')
param industry string = 'Healthcare'

@description('Optional institution name displayed in the frontend AI model access indicator.')
@maxLength(60)
param institutionName string = ''

@description('Optional. Override the built-in German v4_judge system prompt. Empty = paper default.')
param systemPrompt string = ''

@description('Optional, recommended. Entra app registration (client) ID to require user sign-in. Empty = no user auth. Create the app registration yourself - see README.')
param entraClientId string = ''

@description('Entra tenant ID for sign-in. Defaults to the deployment tenant.')
param entraTenantId string = tenant().tenantId

@description('Application package (zip). Defaults to the research GitHub release build.')
param packageUri string = 'https://github.com/groeschel-lab/inconsistency-check/releases/latest/download/app.zip'

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
    institutionName: institutionName
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
