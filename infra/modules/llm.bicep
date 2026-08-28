// LLM module - Azure AI Foundry (AIServices) account + ONE model deployment
// from the paper's Phase-2 panel. Keyless (disableLocalAuth); the app calls it
// via Managed Identity + RBAC. Claude routes via /anthropic/v1, the rest via
// /openai/v1 (backend picks the route from MODEL_FORMAT).

@description('Azure region for the AIServices account.')
param location string

@description('Unique suffix appended to resource names.')
@minLength(3)
@maxLength(8)
param nameSuffix string

@description('Which of the paper\'s five models to deploy.')
@allowed([ 'claude-opus-4-7', 'gpt-5.5', 'mistral-large-3', 'deepseek-v3.2', 'gpt-5.4-nano' ])
param modelProfile string

@description('Requested capacity (thousands of tokens/min); clamped to a safe per-model maximum.')
@minValue(1)
param modelCapacity int = 20

@description('Organization name for Anthropic (Claude) model provider data. Required for Claude; ignored for other models.')
param organizationName string = 'Healthcare organization'

@description('ISO 3166 alpha-2 country code for Anthropic model provider data.')
param countryCode string = 'DE'

@description('Industry for Anthropic model provider data.')
param industry string = 'Healthcare'

// Verified against the live Foundry catalog in swedencentral (2026-08-25).
// maxCapacity = the catalog SKU quota ceiling, used to clamp a default deploy.
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
    // Private only: the app reaches the model over a Private Endpoint (see core.bicep), so clinical text stays on the VNet.
    publicNetworkAccess: 'Disabled'
  }
}

// 2026-05-15-preview: the RP version that honors modelProviderData for Anthropic.
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2026-05-15-preview' = {
  parent: ai
  name: p.name
  sku: { name: p.sku, capacity: effectiveCapacity }
  // Anthropic (Claude) deployments require modelProviderData (marketplace terms);
  // the RP honors it but it is not yet in the Bicep type, hence the BCP037 suppression.
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
// Unified Foundry inference endpoint (serves /openai/v1 and /anthropic/v1).
output endpoint string = 'https://aif-${nameSuffix}.services.ai.azure.com'
output deploymentName string = p.name
output modelFormat string = p.format
output modelLabel string = '${p.format} ${p.name}@${p.version} (${p.sku})'
