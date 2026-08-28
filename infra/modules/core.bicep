// Core infrastructure for Inconsistency Check:
// Azure Functions (Elastic Premium, Linux, Python), keyless Managed-Identity
// storage over Private Endpoints + VNet, App Insights, and the AI Foundry model
// (delegated to ./llm.bicep). All model + storage access is MI + RBAC - no keys,
// no Key Vault. End-user Entra auth is added by a separate module.

@description('Azure region for all resources.')
param location string

@description('Unique suffix for globally unique names (3-8 lowercase).')
@minLength(3)
@maxLength(8)
param nameSuffix string

@description('Which of the paper\'s five models to deploy.')
@allowed([ 'claude-opus-4-7', 'gpt-5.5', 'mistral-large-3', 'deepseek-v3.2', 'gpt-5.4-nano' ])
param modelProfile string

@description('Requested model capacity (thousands of tokens/min); clamped per model.')
@minValue(1)
param modelCapacity int = 20

@description('Organization name for Anthropic (Claude) model provider data.')
param organizationName string = 'Healthcare organization'

@description('ISO 3166 alpha-2 country code for Anthropic model provider data.')
param countryCode string = 'DE'

@description('Industry for Anthropic model provider data.')
param industry string = 'Healthcare'

@description('Optional system-prompt override (empty = built-in v4_judge default).')
param systemPrompt string = ''

@description('Public HTTPS URL of the Function App .zip to run via WEBSITE_RUN_FROM_PACKAGE.')
param packageUri string

@description('Entra app registration (client) ID for end-user sign-in. Empty = no user auth (network-restricted only). You create the app registration yourself - see README.')
param entraClientId string = ''

@description('Entra tenant ID for sign-in. Defaults to the deployment tenant.')
param entraTenantId string = tenant().tenantId

// Built-in role definition IDs
var storageBlobDataOwnerRole = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageQueueDataContributorRole = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorRole = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var cognitiveServicesOpenAIUserRole = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
var cognitiveServicesUserRole = 'a97b65f3-24c7-4388-baec-2e87135dc908'

var storageSubResources = [ 'blob', 'queue', 'table', 'file' ]
var foundryPrivateDnsZones = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

// Storage (Functions runtime - keyless, no shared keys)
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'stlc${nameSuffix}'
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// VNet (Function App integration + private endpoints)
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-lc-${nameSuffix}'
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.40.0.0/16' ] }
  }
}

resource subnetApp 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'snet-app'
  properties: {
    addressPrefix: '10.40.1.0/24'
    delegations: [ { name: 'delegation-app', properties: { serviceName: 'Microsoft.Web/serverFarms' } } ]
  }
}

resource subnetPe 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'snet-pe'
  properties: {
    addressPrefix: '10.40.2.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  dependsOn: [ subnetApp ]
}

// App Service Plan (Elastic Premium - required for keyless storage + VNet)
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-lc-${nameSuffix}'
  location: location
  kind: 'elastic'
  sku: { name: 'EP1', tier: 'ElasticPremium' }
  properties: { reserved: true }
}

// App Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-lc-${nameSuffix}'
  location: location
  kind: 'web'
  properties: { Application_Type: 'web', Request_Source: 'rest' }
}

// AI Foundry model (AIServices account + one deployment)
module llm './llm.bicep' = {
  name: 'llm-${nameSuffix}'
  params: {
    location: location
    nameSuffix: nameSuffix
    modelProfile: modelProfile
    modelCapacity: modelCapacity
    organizationName: organizationName
    countryCode: countryCode
    industry: industry
  }
}

// Handle to the AIServices account so RBAC can be scoped to it.
resource llmAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: 'aif-${nameSuffix}'
}

// Private Endpoints + DNS (Storage over VNet)
resource storageDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for sub in storageSubResources: {
  name: 'privatelink.${sub}.${environment().suffixes.storage}'
  location: 'global'
}]

resource storageDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (sub, i) in storageSubResources: {
  parent: storageDnsZones[i]
  name: 'link-${sub}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}]

resource storagePe 'Microsoft.Network/privateEndpoints@2024-01-01' = [for sub in storageSubResources: {
  name: 'pe-${sub}-lc-${nameSuffix}'
  location: location
  properties: {
    subnet: { id: subnetPe.id }
    privateLinkServiceConnections: [
      {
        name: sub
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [ sub ]
        }
      }
    ]
  }
}]

resource storagePeDnsGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = [for (sub, i) in storageSubResources: {
  parent: storagePe[i]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [ { name: sub, properties: { privateDnsZoneId: storageDnsZones[i].id } } ]
  }
}]

// Private Endpoint + DNS (AI Foundry model over VNet) - keeps clinical text on the tenant network
resource foundryDnsZonesRes 'Microsoft.Network/privateDnsZones@2020-06-01' = [for z in foundryPrivateDnsZones: {
  name: z
  location: 'global'
}]

resource foundryDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (z, i) in foundryPrivateDnsZones: {
  parent: foundryDnsZonesRes[i]
  name: 'link-aif'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}]

resource foundryPe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: 'pe-aif-lc-${nameSuffix}'
  location: location
  properties: {
    subnet: { id: subnetPe.id }
    privateLinkServiceConnections: [
      {
        name: 'aif'
        properties: {
          privateLinkServiceId: llmAccount.id
          groupIds: [ 'account' ]
        }
      }
    ]
  }
  dependsOn: [ llm ]
}

resource foundryPeDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: foundryPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (z, i) in foundryPrivateDnsZones: {
      name: 'zone-${i}'
      properties: { privateDnsZoneId: foundryDnsZonesRes[i].id }
    }]
  }
}

// Function App
var promptSetting = empty(systemPrompt) ? [] : [ { name: 'SYSTEM_PROMPT', value: systemPrompt } ]

// End-user Entra sign-in (Easy Auth) is enabled when a client ID is supplied.
var authEnabled = !empty(entraClientId)

// Dedicated identity used only as the Easy Auth federated credential (keyless, no client secret).
resource authIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (authEnabled) {
  name: 'id-auth-${nameSuffix}'
  location: location
}

var authAppSetting = authEnabled ? [ { name: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID', value: authIdentity!.properties.clientId } ] : []

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'func-lc-${nameSuffix}'
  location: location
  kind: 'functionapp,linux'
  identity: authEnabled ? {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${authIdentity.id}': {}
    }
  } : {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    virtualNetworkSubnetId: subnetApp.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: union([
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: packageUri }
        // Route only private traffic through the VNet so the package download reaches the public zip URL.
        { name: 'WEBSITE_VNET_ROUTE_ALL', value: '0' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
        // Elastic Premium: skip the pre-warmed placeholder for a reliable cold start.
        { name: 'WEBSITE_USE_PLACEHOLDER', value: '0' }
        { name: 'AZURE_AI_ENDPOINT', value: llm.outputs.endpoint }
        { name: 'AZURE_AI_DEPLOYMENT', value: llm.outputs.deploymentName }
        { name: 'MODEL_FORMAT', value: llm.outputs.modelFormat }
      ], promptSetting, authAppSetting)
    }
  }
  dependsOn: [ storagePeDnsGroups ]
}

// End-user Entra sign-in (Easy Auth). The operator creates the app registration and a
// federated credential trusting the identity above (see README); no client secret is used.
var effectiveTenantId = empty(entraTenantId) ? tenant().tenantId : entraTenantId

resource authSettings 'Microsoft.Web/sites/config@2023-12-01' = if (authEnabled) {
  parent: functionApp
  name: 'authsettingsV2'
  properties: {
    platform: { enabled: true }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureactivedirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: '${environment().authentication.loginEndpoint}${effectiveTenantId}/v2.0'
          clientId: entraClientId
          clientSecretSettingName: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID'
        }
        validation: {
          allowedAudiences: [ 'api://${entraClientId}', entraClientId ]
        }
      }
    }
    login: {
      // Disabled: the token store needs writable storage; this app only gates sign-in and stores no tokens.
      tokenStore: { enabled: false }
    }
  }
}

// RBAC (Function MI -> storage + Foundry)
resource storageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, storageBlobDataOwnerRole)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRole)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, storageQueueDataContributorRole)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRole)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, storageTableDataContributorRole)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRole)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource llmOpenAIRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(llmAccount.id, functionApp.id, cognitiveServicesOpenAIUserRole)
  scope: llmAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRole)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource llmCognitiveRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(llmAccount.id, functionApp.id, cognitiveServicesUserRole)
  scope: llmAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRole)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output foundryEndpoint string = llm.outputs.endpoint
output modelDeployment string = llm.outputs.deploymentName
output modelLabel string = llm.outputs.modelLabel
output authIdentityClientId string = authEnabled ? authIdentity!.properties.clientId : ''
output authIdentityPrincipalId string = authEnabled ? authIdentity!.properties.principalId : ''
output authFederationIssuer string = authEnabled ? '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0' : ''
