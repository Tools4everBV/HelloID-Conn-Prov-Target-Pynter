#################################################
# HelloID-Conn-Prov-Target-Pynter-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-PynterError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = [xml]($httpErrorObj.ErrorDetails)
            $errorNode = $errorDetailsObject.SelectSingleNode("//*[local-name()='Body']//*[local-name()='Fault']")
            if ($errorNode.Reason){
                $httpErrorObj.FriendlyMessage = $errorNode.Reason.Text.'#text'
            }
        } catch {
            $httpErrorObj.FriendlyMessage = $_.Exception.Message
        }
        Write-Output $httpErrorObj
    }
}

function New-PynterSoapXmlBody {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $SoapMethod,

        [Parameter(Mandatory)]
        [hashtable]
        $Parameters
    )

    try {
        $namespace = 'http://tempuri.org/'
        $xml = [System.Xml.XmlDocument]::new()
        $envelope = $xml.CreateElement('soap12', 'Envelope', 'http://www.w3.org/2003/05/soap-envelope')
        $null = $envelope.SetAttribute('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance')
        $null = $envelope.SetAttribute('xmlns:xsd', 'http://www.w3.org/2001/XMLSchema')

        $body = $xml.CreateElement('soap12', 'Body', 'http://www.w3.org/2003/05/soap-envelope')
        $methodElement = $xml.CreateElement($SoapMethod, $namespace)

        $usernameNode = $xml.CreateElement('username', $namespace)
        $null = $usernameNode.InnerText = $actionContext.Configuration.UserName
        $null = $methodElement.AppendChild($usernameNode)

        $passwordNode = $xml.CreateElement('password', $namespace)
        $null = $passwordNode.InnerText = $actionContext.Configuration.Password
        $null = $methodElement.AppendChild($passwordNode)

        foreach ($key in $Parameters.Keys) {
            $paramNode = $xml.CreateElement($key, $namespace)

            if ($Parameters[$key] -is [PSCustomObject]) {
                foreach ($prop in $Parameters[$key].PSObject.Properties) {
                    $subNode = $xml.CreateElement($prop.Name, $namespace)
                    $value = $prop.Value
                    if (-not[string]::IsNullOrEmpty($value)){
                        if ($prop.Name -eq "contractStartTime" -or $prop.Name -eq "contractEndTime") {
                            $dateValue = [datetime]$value
                            $subNode.SetAttribute('xsi:type', 'xsd:dateTime')
                            $subNode.InnerText = $dateValue.ToString("yyyy-MM-ddTHH:mm:ss")
                        } elseif ($value -is [bool]) {
                            $subNode.SetAttribute('xsi:type', 'xsd:boolean')
                            $subNode.InnerText = $value.ToString().ToLower()
                        } else {
                            $subNode.InnerText = $value
                        }
                        $null = $paramNode.AppendChild($subNode)
                    }
                }
            } else {
                $value = $Parameters[$key]
                if ($value -is [bool]) {
                    $paramNode.SetAttribute('xsi:type', 'xsd:boolean')
                    $paramNode.InnerText = $value.ToString().ToLower()
                } else {
                    $paramNode.InnerText = $value
                }
            }
            $null = $methodElement.AppendChild($paramNode)
        }

        $null = $body.AppendChild($methodElement)
        $null = $envelope.AppendChild($body)
        $null = $xml.AppendChild($envelope)

        Write-Output $xml.OuterXml
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Invoke-PynterSOAPRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Uri,


        [Parameter(Mandatory)]
        [string]
        $Body,

        [Parameter(Mandatory)]
        [string]
        $Method
    )

    try {
        $splatParams = @{
            Uri         = $Uri
            Body        = $Body
            Method      = $Method
            ContentType = 'application/soap+xml; charset=utf-8'
        }
        [xml]$xmlResponse = Invoke-RestMethod @splatParams
        $success = $xmlResponse.SelectSingleNode("//*[local-name()='Body']//*[local-name()='Success']")
        if ($($success.'#text') -eq 'true') {
            $contentsNode = $xmlResponse.SelectSingleNode("//*[local-name()='Body']//*[local-name()='Contents']")
            if ($null -ne $contentsNode) {
                $obj = [PSCustomObject]@{}
                foreach ($node in $contentsNode.ChildNodes) {
                    $obj | Add-Member -MemberType NoteProperty -Name $node.LocalName -Value $node.InnerText
                }
                Write-Output $obj
            }
        } elseif ($($success.'#text') -eq 'false') {
            $errorNode = $xmlResponse.SelectSingleNode("//*[local-name()='Body']//*[local-name()='Error']")
            if ($null -ne $errorNode) {
                throw $($errorNode.'#text')
            } else {
                throw 'An error occurred, but no error details were found in the response.'
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Verifying if a Pynter account exists'
    # Create GetPersonByExternalId XML body
    # https://{customer}.pynter.nl/service/apiservice.asmx?op=GetPersonByPynterId
    $splatGetPersonByPynterIdXmlBody = @{
        SoapMethod = 'GetPersonByPynterId'
        Parameters = @{ pynterPersonId = $actionContext.References.Account }
    }
    $getPersonByPynterIdXmlBody = New-PynterSoapXmlBody @splatGetPersonByPynterIdXmlBody
    try {
        $splatGetUserParams = @{
            Uri    = "$($actionContext.configuration.BaseUrl)/service/apiService.asmx"
            Body   = $getPersonByPynterIdXmlBody
            Method = 'POST'
        }
        $correlatedAccount = Invoke-PynterSOAPRequest @splatGetUserParams
        $outputContext.PreviousData = $correlatedAccount
    } catch {
        if ($_.Exception.Message -eq 'Person not found.'){
            $correlatedAccount = $null
        } else {
            throw
        }
    }

    # Always compare the account against the current account in target system
    if ($null -ne $correlatedAccount) {
            $correlatedAccount.PSObject.Properties | ForEach-Object {
                if ($null -eq $_.Value) {
                    $_.Value = ''
                }
            }

            $actionContext.Data.PSObject.Properties | ForEach-Object {
                if ($null -eq $_.Value) {
                    $_.Value = ''
                }
            }

        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged.Name -contains 'ManagerExternalIdentifier'){
            # Verify if manager exists. If not, we remove the 'ManagerExternalIdentifier' from the actionContext.Data
            Write-Information 'Creating GetPersonManagerByExternalId Xml body'
            $splatGetPersonManagerByExternalIdXmlBody = @{
                SoapMethod = 'GetPersonByExternalId'
                Parameters = @{ externalId = $actionContext.Data.ManagerExternalIdentifier }
            }
            $getPersonManagerByExternalIdXmlBody = New-PynterSoapXmlBody @splatGetPersonManagerByExternalIdXmlBody
            try {
                $splatGetUserParams = @{
                    Uri    = "$($actionContext.configuration.BaseUrl)/service/apiService.asmx"
                    Body   = $getPersonManagerByExternalIdXmlBody
                    Method = 'POST'
                }
                $null = Invoke-PynterSOAPRequest @splatGetUserParams
            } catch {
                if ($_.Exception.Message -eq 'Person not found.'){
                    Write-Warning "Manager with externalId: [$($actionContext.Data.ManagerExternalIdentifier)] could not be found"
                    $actionContext.Data.PSObject.Properties.Remove('ManagerExternalIdentifier')
                } else {
                    throw
                }
            }
        }

        if ($propertiesChanged) {
            $action = 'UpdateAccount'
        } else {
            $action = 'NoChanges'
        }
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {
            Write-Information "Updating Pynter account with accountReference: [$($actionContext.References.Account)]"
            Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"

            # Create UpdatePerson XML body
            # https://{customer}.pynter.nl/service/apiservice.asmx?op=UpdatePerson
            Write-Information 'Creating UpdatePerson Xml body'
            $splatUpdatePersonXmlBody = @{
                SoapMethod = 'UpdatePerson'
                Parameters = @{ pynterPersonId = $actionContext.References.Account; personUpdate = $actionContext.Data }
            }
            $updatePersonXmlBody = New-PynterSoapXmlBody @splatUpdatePersonXmlBody

            if (-not($actionContext.DryRun -eq $true)) {
                $splatUpdatePersonRequest = @{
                    Uri    = "$($actionContext.configuration.BaseUrl)/service/apiService.asmx"
                    Body   = $updatePersonXmlBody
                    Method = 'POST'
                }
                $null = Invoke-PynterSOAPRequest @splatUpdatePersonRequest
            } else {
                Write-Information "[DryRun] Update Pynter account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to Pynter account with accountReference: [$($actionContext.References.Account)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Pynter account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Pynter account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could have been deleted"
                    IsError = $true
                })
            break
        }
    }
} catch {
    $outputContext.Success  = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-PynterError -ErrorObject $ex
        $auditMessage = "Could not update Pynter account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Pynter account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
