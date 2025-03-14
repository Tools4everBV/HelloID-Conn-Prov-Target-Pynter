#################################################
# HelloID-Conn-Prov-Target-Pynter-Create
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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        # Create GetPersonByExternalId XML body
        # https://{customer}.pynter.nl/service/apiservice.asmx?op=GetPersonByExternalId
        Write-Information 'Creating GetPersonByExternalId Xml body'
        $splatGetPersonByExternalIdXmlBody = @{
            SoapMethod = 'GetPersonByExternalId'
            Parameters = @{ externalId = $correlationValue }
        }
        $getPersonByExternalIdXmlBody = New-PynterSoapXmlBody @splatGetPersonByExternalIdXmlBody
        try {
            $splatGetUserParams = @{
                Uri    = "$($actionContext.configuration.BaseUrl)/service/apiService.asmx"
                Body   = $getPersonByExternalIdXmlBody
                Method = 'POST'
            }
            $correlatedAccount = Invoke-PynterSOAPRequest @splatGetUserParams
        } catch {
            if ($_.Exception.Message -eq 'Person not found.'){
                $correlatedAccount = $null
            } else {
                throw
            }
        }

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
                $actionContext.Data.PSObject.Properties.Remove('ManagerExternalIdentifier')
            } else {
                throw
            }
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'CorrelateAccount'
    } else {
        $action = 'CreateAccount'
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            Write-Information 'Creating and correlating Pynter account'
            $actionContext.Data.Blocked = [System.Convert]::ToBoolean($actionContext.Data.Blocked)

            # Create CreatePerson XML body
            # https://{customer}.pynter.nl/service/apiservice.asmx?op=CreatePerson
            Write-Information 'Creating CreatePerson Xml body'
            $splatCreatePersonXmlBody = @{
                SoapMethod = 'CreatePerson'
                Parameters = @{ personCreate = $actionContext.Data }
            }
            $createPersonXmlBody = New-PynterSoapXmlBody @splatCreatePersonXmlBody

            if (-not($actionContext.DryRun -eq $true)) {
                $splatCreatePersonRequest = @{
                    Uri    = "$($actionContext.configuration.BaseUrl)/service/apiService.asmx"
                    Body   = $createPersonXmlBody
                    Method = 'POST'
                }
                $createdAccount = Invoke-PynterSOAPRequest @splatCreatePersonRequest
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.'#text'
            } else {
                Write-Information '[DryRun] Create and correlate Pynter account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Pynter account'
            $outputContext.Data = $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.Id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-PynterError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Pynter account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate Pynter account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}