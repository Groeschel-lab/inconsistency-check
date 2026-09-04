// Deploy the Function App, private networking, model module, identities, and RBAC.

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

@description('Optional institution name displayed in the frontend AI model access indicator.')
@maxLength(60)
param institutionName string = ''

@description('Optional. Override the built-in German v4_judge system prompt. Empty = paper default.')
param systemPrompt string = ''

@description('Application package (zip). Defaults to the research GitHub release build.')
param packageUri string

@description('Optional, recommended. Entra app registration (client) ID to require user sign-in. Empty = no user auth. Create the app registration yourself - see README.')
param entraClientId string = ''

@description('Entra tenant ID for sign-in. Defaults to the deployment tenant.')
param entraTenantId string = tenant().tenantId

// Built-in role definition IDs.
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

// Function runtime storage.
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

// Function VNet and private endpoint subnet.
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

// Elastic Premium supports VNet integration and keyless storage.
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-lc-${nameSuffix}'
  location: location
  kind: 'elastic'
  sku: { name: 'EP1', tier: 'ElasticPremium' }
  properties: { reserved: true }
}

// Application Insights telemetry.
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-lc-${nameSuffix}'
  location: location
  kind: 'web'
  properties: { Application_Type: 'web', Request_Source: 'rest' }
}

// Foundry account and model deployment.
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

// Scope model role assignments to the Foundry account.
resource llmAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: 'aif-${nameSuffix}'
}

// Private endpoints and DNS for Function storage.
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

// Private endpoint and DNS for Foundry.
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
var institutionSetting = empty(institutionName) ? [] : [ { name: 'INSTITUTION_NAME', value: institutionName } ]
var functionAppName = 'func-lc-${nameSuffix}'

// Enable Easy Auth when a client ID is supplied.
var authEnabled = !empty(entraClientId)

// Identity used by the Easy Auth federated credential.
resource authIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (authEnabled) {
  name: 'id-auth-${nameSuffix}'
  location: location
}

var authAppSetting = authEnabled ? [ { name: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID', value: authIdentity!.properties.clientId } ] : []

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
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
      cors: {
        allowedOrigins: [ 'https://${functionAppName}.azurewebsites.net' ]
        supportCredentials: false
      }
      appSettings: union([
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: packageUri }
        // Keep public package downloads outside VNet routing.
        { name: 'WEBSITE_VNET_ROUTE_ALL', value: '0' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
        // Disable the pre-warmed placeholder for reliable startup.
        { name: 'WEBSITE_USE_PLACEHOLDER', value: '0' }
        { name: 'AZURE_AI_ENDPOINT', value: llm.outputs.endpoint }
        { name: 'AZURE_AI_DEPLOYMENT', value: llm.outputs.deploymentName }
        { name: 'MODEL_FORMAT', value: llm.outputs.modelFormat }
      ], promptSetting, institutionSetting, authAppSetting)
    }
  }
  dependsOn: [ storagePeDnsGroups ]
}

// Easy Auth uses the operator-managed app registration documented in the README.
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
      // The app does not use the Easy Auth token store.
      tokenStore: { enabled: false }
    }
  }
}

// Function identity role assignments.
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

output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output foundryEndpoint string = llm.outputs.endpoint
output modelDeployment string = llm.outputs.deploymentName
output modelLabel string = llm.outputs.modelLabel
output authIdentityClientId string = authEnabled ? authIdentity!.properties.clientId : ''
output authIdentityPrincipalId string = authEnabled ? authIdentity!.properties.principalId : ''
output authFederationIssuer string = authEnabled ? '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0' : ''
