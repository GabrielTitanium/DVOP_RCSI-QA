# RCSI-QA Deployment Pipeline

This repository contains an Azure DevOps YAML pipeline for deploying and updating the RCSI-QA environment.

## Overview

The main pipeline definition is in [azure-pipelines.yml](azure-pipelines.yml). It is a **multi-stage** deployment pipeline that:
- Stops IIS and enables a maintenance page
- Downloads build artifacts from a upstream Salud Services pipeline
- Installs/updates the Origin application and configures IIS
- Runs database migrations
- Restarts IIS and uploads customer packages

The pipeline uses variables from the variable group `RCSI_QA` and runs on an agent in the `Dublin` pool constrained by `agent.name -equals RCSI-QA`.

### External Pipeline Resource

The `resources` section references another pipeline:
- Project: `Titanium`
- Pipeline name: `Salud Services Trunk`
- Alias: `SaludServicesTrunk`
- Trigger: when that pipeline is tagged with `ReleaseReady`

Artifacts from that pipeline (e.g., `CustomerPackages.zip`, `Setup_Origin.msi`) are downloaded and used during deployment.

## Stages

### 1. Deploy_Approval

- Environment: `RCSI-QA` (drives manual approvals / checks in Azure DevOps).
- Key actions:
  - Lists repository contents (debug step).
  - Stops IIS using [scripts/Stop-IIS.ps1](scripts/Stop-IIS.ps1).
  - Copies `Server.ps1` and `maintenance.html` to `C:\MaintenancePage\MaintenancePage`.
  - Ensures a scheduled task **MaintenanceServer** exists and points to `C:\MaintenancePage\MaintenancePage\Server.ps1`.
  - Starts the maintenance task ("Maintenance ON").

### 2. FetchSaludArtifacts

- Downloads artifacts from the `SaludServicesTrunk` pipeline.
- Uses [scripts/Copy-Artifacts.ps1](scripts/Copy-Artifacts.ps1) to copy:
  - `Setup_Origin.msi`
  - `CustomerPackages.zip`
  into `C:\Build\`.
- Extracts `CustomerPackages.zip` to `C:\Build\CustomerPackages`.

### 3. InstallApplication

- Clears install-related registry values using [scripts/Clear-Registry.ps1](scripts/Clear-Registry.ps1).
- Installs the Origin application using [scripts/Install-Origin.ps1](scripts/Install-Origin.ps1) with parameters for:
  - Installer path and log file
  - Install directory and features
  - Website and application pool
  - Database connection info (from environment variables `DB_IP`, `DB_NAME`, `SQL_USER`, `SQL_PASSWORD`)
- Configures IIS using [scripts/Configure-IIS.ps1](scripts/Configure-IIS.ps1).

### 4. DatabaseMigration

- Runs database migration via [scripts/Run-DatabaseMigration.ps1](scripts/Run-DatabaseMigration.ps1) pointing to
  `Titanium.Migration.DataAccess.Migration.exe` and using DB parameters from environment variables.
- If the job finishes with `SucceededWithIssues`, displays a migration message using
  [scripts/Migration-Message.ps1](scripts/Migration-Message.ps1).

### 5. UploadCustomerPackages

- Starts IIS using [scripts/Start-IIS.ps1](scripts/Start-IIS.ps1).
- Turns off maintenance:
  - Ends the **MaintenanceServer** scheduled task.
  - Optionally kills any remaining `Server.ps1` PowerShell process.
- Configures customer package upload web services using
  [scripts/Create-UploadWebServices.ps1](scripts/Create-UploadWebServices.ps1), with parameters:
  - `-url` (API URL)
  - `-username` / `-password` (admin credentials)
  - `-clinic` (clinic key)
  - `-filepath` (path to CustomerPackages XML reference folder)
- Copies [scripts/Run-UploadPackages.ps1](scripts/Run-UploadPackages.ps1) into the customer packages reference path.
- Runs the upload script from `$(CustomerPackagesUploadScriptPath)` to install/upload the packages.

## Key Scripts

Most operational logic is encapsulated in the PowerShell scripts under [scripts](scripts):
- [scripts/Stop-IIS.ps1](scripts/Stop-IIS.ps1): Stops the `w3svc` service and waits until IIS is fully stopped.
- [scripts/Start-IIS.ps1](scripts/Start-IIS.ps1): Starts the `w3svc` service.
- [scripts/Clear-Registry.ps1](scripts/Clear-Registry.ps1): Backs up and clears installation-related registry keys.
- [scripts/Install-Origin.ps1](scripts/Install-Origin.ps1): Installs/upgrades the Origin application via MSI.
- [scripts/Configure-IIS.ps1](scripts/Configure-IIS.ps1): Configures IIS sites/applications for Origin.
- [scripts/Run-DatabaseMigration.ps1](scripts/Run-DatabaseMigration.ps1): Executes DB migration executable.
- [scripts/Create-UploadWebServices.ps1](scripts/Create-UploadWebServices.ps1): Configures API/web services needed to upload customer packages.
- [scripts/Run-UploadPackages.ps1](scripts/Run-UploadPackages.ps1): Wrapper that uploads customer packages defined in the reference folder.

## Running the Pipeline

1. Ensure the variable group `RCSI_QA` exists and contains required values such as:
   - `databaseName`, `databaseUser`, `databasePassword`, `privateDB`
   - `admin_username`, `admin_password`, `clinic_key`, `API`
2. Ensure the upstream pipeline `Salud Services Trunk` in project `Titanium` publishes the artifacts `CustomerPackages.zip` and `Setup_Origin.msi` in a `drop` artifact.
3. Queue the pipeline in Azure DevOps or let it be triggered by a `ReleaseReady` tag on the `Salud Services Trunk` pipeline.
4. Approve the `RCSI-QA` environment deployment when prompted.

Once complete, IIS will be running the updated Origin application, the database will be migrated, and customer packages will be uploaded for the specified clinic.
