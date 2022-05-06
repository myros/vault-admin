# vault-admin

## Migrate secrets

Migrate your secrets from one Vault server/Namespace/path to other Vault server/Namespace/Engine/Path.

### Options (.env file)

| Var | Description | Values |
|-|-|-|
| V1_ADDR | Source Vault Address | http://localhost:8200 |
| V1_NAMESPACE | Source Namespace | root if not Vault enterprise |
| V1_KV | Source Vault Engine; Must end with / | 
| V1_BASE_PATH | Path to Secrets to migrate; Can Be Empty; Must end with / | 
| V1_TOKEN | Source Server Vault Token
| V2_ADDR | Destination Vault Address | http://localhost:8200 |
| V2_NAMESPACE | Destination Namespace | root if not Vault enterprise |
| V2_KV | Destination Vault Engine; Must end with / | 
| V2_BASE_PATH | Path to Secrets to migrate; Can Be Empty; Must end with / | 
| V2_TOKEN | Destination Server Vault Token | 
| DELETE_DESTINATION_SECRET | Delete destination secrets before copying |
| MIGRATE_SECRETS_VERSIONS | Migrate secret with versions | 

## Export policies