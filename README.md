# HelloID-Conn-Prov-Target-Pynter

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Pynter](#helloid-conn-prov-target-pynter)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Available lifecycle actions](#available-lifecycle-actions)
    - [Field mapping](#field-mapping)
  - [Remarks](#remarks)
    - [Namespace](#namespace)
    - [Dynamic SOAP envelope derived from fieldMapping](#dynamic-soap-envelope-derived-from-fieldmapping)
      - [Example SOAP envelope for `GetPersonByExternalId`](#example-soap-envelope-for-getpersonbyexternalid)
    - [Required fields when updating](#required-fields-when-updating)
      - [Compare logic within the _update_ lifecycle action](#compare-logic-within-the-update-lifecycle-action)
  - [Development resources](#development-resources)
    - [SOAP methods](#soap-methods)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Pynter_ is a _target_ connector. _Pynter_ provides a set of SOAP APIs that allow you to programmatically interact with its data. These APIs use XML-based requests and responses, following the SOAP protocol for structured communication.

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting                   | Description                                                                          | Mandatory |
| ------------------------- | ------------------------------------------------------------------------------------ | --------- |
| UserName                  | The UserName to connect to the API                                                   | Yes       |
| Password                  | The Password to connect to the API                                                   | Yes       |
| BaseUrl                   | The URL to the API                                                                   | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Pynter_ to a person in _HelloID_.

| Setting                   | Value                |
| ------------------------- | -------------------- |
| Enable correlation        | `True`               |
| Person correlation field  | `ExternalId`         |
| Account correlation field | `ExternalIdentifier` |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Available lifecycle actions

The following lifecycle actions are available:

| Action             | Description                                                                     |
| ------------------ | ------------------------------------------------------------------------------- |
| create.ps1         | Creates a new account.                                                          |
| delete.ps1         | Removes an existing account or entity.                                          |
| disable.ps1        | Disables an account, preventing access without permanent removal.               |
| enable.ps1         | Enables an account, granting access.                                            |
| update.ps1         | Updates the attributes of an account.                                           |
| configuration.json | Contains the connection settings and general configuration for the connector.   |
| fieldMapping.json  | Defines mappings between person fields and target system person account fields. |

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

## Remarks

### Namespace

Currently the function `New-PynterSoapXmlBody` uses a default namespace which is set to: `http://tempuri.org/`. This value is usually reserved for development environemts only. For production environments, the value of the namespace might be subject to change. Make sure to verify and update this accordingly during the first implementation.

### Dynamic SOAP envelope derived from fieldMapping

The `New-PynterSoapXmlBody` function is responsible for creating the SOAP envelope. It takes two parameters:

- **`SOAPMethod`** – Defines the specific SOAP method being called.
- **`Parameters`** – Contains the key-value pairs for the SOAP body, derived from `actionContext.Data` or the [correlation configuration.](#correlation-configuration)

Since `actionContext.Data` dynamically provides the parameter names and values, this function allows full flexibility in constructing the SOAP envelope. You can easily extend `actionContext.Data` with additional fields, as long as the names match the expected SOAP method parameters.

#### Example SOAP envelope for `GetPersonByExternalId`

Consider the following PowerShell code:

```powershell
$splatGetPersonByExternalIdXmlBody = @{
    SoapMethod = 'GetPersonByExternalId'
    Parameters = @{ externalId = '123456' }
}
New-PynterSoapXmlBody @splatGetPersonByExternalIdXmlBody
```

This will result in the following SOAP envelope:

```xml
<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
    <soap12:Body>
        <GetPersonByExternalId xmlns="http://tempuri.org/">
            <username>MyUserName</username>
            <password>MyPassword</password>
            <externalId>123456</externalId>
        </GetPersonByExternalId>
    </soap12:Body>
</soap12:Envelope>
```

- **username** and **password** are automatically derived from `actionContext.Configuration`, ensuring authentication.
- **externalId** is a dynamic input and specified in the `-Parameters` parameter.

### Required fields when updating

The fields: `FirstName`, `FamilyName`, `ExternalIdentifier`, and `Email` must always be provided when updating an account (or performing operations like enabling, disabling, or deleting an account). The values send back are the ones that come from the `$correlatedAccount`' object.

#### Compare logic within the _update_ lifecycle action

The _update_ lifecycle action does contain our standard compare logic. However, contrary to the documentation, its worth to note that; even though properties are compared and changed properties are logged, __ALL__ properties will be updated.

## Development resources

### SOAP methods

The following endpoints are used by the connector

| SOAP method           | Documentation URI                                                                                          | Lifecycle actions                   |
| --------------------- | ---------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| GetPersonByExternalId | [Retrieve user information](https://{customer}.pynter.nl/service/apiservice.asmx?op=GetPersonByExternalId) | create,update,enable,disable,delete |
| CreatePerson          | [Create user account](https://{customer}.pynter.nl/service/apiservice.asmx?op=CreatePerson)                | create                              |
| UpdatePerson          | [Update user account](https://{customer}.pynter.nl/service/apiservice.asmx?op=UpdatePerson)                | update,enable,disable,delete        |

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/