// Deploy one model from the paper's validation panel to an Azure AI Services account.

@description('Azure region (EU). Claude Opus 4.7 (the paper reference model) is only in swedencentral.')
param location string

@description('Short unique suffix for resource names (3-8 lowercase letters/digits, e.g. logic1).')
@minLength(3)
@maxLength(8)
param nameSuffix string

@description('Which of the paper\'s five models to deploy. Claude Opus 4.7 is the validation reference.')
@allowed([ 'claude-opus-4-7', 'gpt-5.5', 'mistral-large-3', 'deepseek-v3.2', 'gpt-5.4-nano' ])
param modelProfile string

@description('Requested model capacity (thousands of tokens/min); clamped to a safe per-model maximum.')
@minValue(1)
param modelCapacity int = 20

@description('Organization name for the model provider data.')
param organizationName string = 'Healthcare organization'

@description('ISO 3166 alpha-2 country code for the model provider data.')
param countryCode string = 'DE'

@description('Industry for the model provider data.')
param industry string = 'Healthcare'

// Catalog values to be verified in the target Azure region.
// maxCapacity clamps the requested deployment capacity.
var profiles = {
  'claude-opus-4-7': { format: 'Anthropic',  name: 'claude-opus-4-7', version: '1',          sku: 'GlobalStandard', maxCapacity: 40 }
  'gpt-5.5':         { format: 'OpenAI',      name: 'gpt-5.5',         version: '2026-04-24', sku: 'GlobalStandard', maxCapacity: 1000 }
  'mistral-large-3': { format: 'Mistral AI',  name: 'Mistral-Large-3', version: '1',          sku: 'GlobalStandard', maxCapacity: 20 }
  'deepseek-v3.2':   { format: 'DeepSeek',    name: 'DeepSeek-V3.2',   version: '1',          sku: 'GlobalStandard', maxCapacity: 20 }
  'gpt-5.4-nano':    { format: 'OpenAI',      name: 'gpt-5.4-nano',    version: '2026-03-17', sku: 'GlobalStandard', maxCapacity: 5000 }
}
var p = profiles[modelProfile]
var effectiveCapacity = min(modelCapacity, p.maxCapacity)

resource ai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'aif-${nameSuffix}'
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: 'aif-${nameSuffix}'
    disableLocalAuth: true
    // Route model traffic through the private endpoint.
    publicNetworkAccess: 'Disabled'
  }
}

// This preview API supports Anthropic modelProviderData.
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2026-05-15-preview' = {
  parent: ai
  name: p.name
  sku: { name: p.sku, capacity: effectiveCapacity }
  // Bicep types do not yet expose modelProviderData.
  properties: p.format == 'Anthropic' ? {
    model: { format: p.format, name: p.name, version: p.version }
    #disable-next-line BCP037
    modelProviderData: {
      industry: industry
      organizationName: organizationName
      countryCode: countryCode
    }
  } : {
    model: { format: p.format, name: p.name, version: p.version }
  }
}

output accountId string = ai.id
output accountName string = ai.name
// Unified endpoint for OpenAI and Anthropic routes.
output endpoint string = 'https://aif-${nameSuffix}.services.ai.azure.com'
output deploymentName string = p.name
output modelFormat string = p.format
output modelLabel string = '${p.format} ${p.name}@${p.version} (${p.sku})'
