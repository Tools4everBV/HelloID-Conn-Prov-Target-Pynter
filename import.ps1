#################################################
# HelloID-Conn-Prov-Target-Pynter-Import-Persons
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
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
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
            if ($errorNode.Reason) {
                $httpErrorObj.FriendlyMessage = $errorNode.Reason.Text.'#text'
            }
        }
        catch {
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
        $null = $usernameNode.InnerText = $actionContext.configuration.UserName
        $null = $methodElement.AppendChild($usernameNode)

        $passwordNode = $xml.CreateElement('password', $namespace)
        $null = $passwordNode.InnerText = $actionContext.configuration.Password
        $null = $methodElement.AppendChild($passwordNode)

        foreach ($key in $Parameters.Keys) {
            $paramNode = $xml.CreateElement($key, $namespace)

            if ($Parameters[$key] -is [PSCustomObject]) {
                foreach ($prop in $Parameters[$key].PSObject.Properties) {
                    $subNode = $xml.CreateElement($prop.Name, $namespace)
                    $value = $prop.Value
                    if (-not[string]::IsNullOrEmpty($value)) {
                        if ($prop.Name -eq "contractStartTime" -or $prop.Name -eq "contractEndTime") {
                            $dateValue = [datetime]$value
                            $subNode.SetAttribute('xsi:type', 'xsd:dateTime')
                            $subNode.InnerText = $dateValue.ToString("yyyy-MM-ddTHH:mm:ss")
                        }
                        elseif ($value -is [bool]) {
                            $subNode.SetAttribute('xsi:type', 'xsd:boolean')
                            $subNode.InnerText = $value.ToString().ToLower()
                        }
                        else {
                            $subNode.InnerText = $value
                        }
                        $null = $paramNode.AppendChild($subNode)
                    }
                }
            }
            else {
                $value = $Parameters[$key]
                if ($value -is [bool]) {
                    $paramNode.SetAttribute('xsi:type', 'xsd:boolean')
                    $paramNode.InnerText = $value.ToString().ToLower()
                }
                else {
                    $paramNode.InnerText = $value
                }
            }
            $null = $methodElement.AppendChild($paramNode)
        }

        $null = $body.AppendChild($methodElement)
        $null = $envelope.AppendChild($body)
        $null = $xml.AppendChild($envelope)

        Write-Output $xml.OuterXml
    }
    catch {
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
        }
        elseif ($($success.'#text') -eq 'false') {
            $errorNode = $xmlResponse.SelectSingleNode("//*[local-name()='Body']//*[local-name()='Error']")
            if ($null -ne $errorNode) {
                throw $($errorNode.'#text')
            }
            else {
                throw 'An error occurred, but no error details were found in the response.'
            }
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Invoke-PynterAllEmployeesSOAPRequest {
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
            $contentsNode = $xmlResponse.SelectNodes("//*[local-name()='Body']//*[local-name()='Contents']//*[local-name()='BasicPersonInfo']")
            $employees = [System.Collections.Generic.List[PSCustomObject]]::new() 

            foreach ($node in $contentsNode) {
                $employeeObj = [PSCustomObject]@{}
                foreach ($childnode in $node.ChildNodes) {
                    $employeeObj | Add-Member -MemberType NoteProperty -Name $childnode.LocalName -Value $childnode.InnerText
                }
                $employees.Add($employeeObj)
            }

            Write-Output $employees
        }
        elseif ($($success.'#text') -eq 'false') {
            $errorNode = $xmlResponse.SelectSingleNode("//*[local-name()='Body']//*[local-name()='Error']")
            if ($null -ne $errorNode) {
                throw $($errorNode.'#text')
            }
            else {
                throw 'An error occurred, but no error details were found in the response.'
            }
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

try {
    # Create GetAllBasicPersonInfo XML body
    # https://{customer}.pynter.nl/service/apiservice.asmx?op=GetAllBasicPersonInfo
    Write-Information 'Creating GetAllBasicPersonInfo Xml body'
    $splatAllBasicPersonInforXmlBody = @{
        SoapMethod = 'GetAllBasicPersonInfo'    
        Parameters = @{}        
    }
    $getAllBasicPersonInfoXmlBody = New-PynterSoapXmlBody @splatAllBasicPersonInforXmlBody
    
    try {
        $splatGetUserParams = @{
            Uri    = "$($actionContext.configuration.BaseUrl)/service/apiService.asmx"
            Body   = $getAllBasicPersonInfoXmlBody
            Method = 'POST'
        }
        $importedAccounts = Invoke-PynterAllEmployeesSOAPRequest @splatGetUserParams        
    }
    catch {
        if ($_.Exception.Message -eq 'Persons not found.') {
            $importedAccounts = $null
        }
        else {
            throw
        }
    }    

    Write-Information 'Starting account data import'
    
    # Map the imported data to the account field mappings
    foreach ($importedAccount in $importedAccounts) {

        $splatGetPersonByPynterIdXmlBody = @{
            SoapMethod = 'GetPersonByPynterId'
            Parameters = @{ pynterPersonId = $importedAccount.PynterId }
        }
        $getPersonByPynterIdXmlBody = New-PynterSoapXmlBody @splatGetPersonByPynterIdXmlBody

        try {
            $splatGetUserParams = @{
                Uri    = "$($actionContext.configuration.BaseUrl)/service/apiService.asmx"
                Body   = $getPersonByPynterIdXmlBody
                Method = 'POST'
            }

            $correlatedAccount = Invoke-PynterSOAPRequest @splatGetUserParams            
        }
        catch {
            if ($_.Exception.Message -eq 'Person not found.') {
                $correlatedAccount = $null
            }
            else {
                throw
            }       
        }
        
        if ($null -ne $correlatedAccount) {            
            $surName = if (!([string]::IsNullOrEmpty($correlatedAccount.insertion))) { $correlatedAccount.insertion + ' ' + $correlatedAccount.familyname } else { $importedAccount.familyname }
            $displayName = $correlatedAccount.firstname + ' ' + $surName

            if ([string]::IsNullOrEmpty($correlatedAccount.Email)) {
                $correlatedAccount.Email = $correlatedAccount.Id
            }
            
            Write-Output @{
                AccountReference = $correlatedAccount.Id
                DisplayName      = $displayName
                UserName         = $correlatedAccount.Email
                Enabled          = if ($correlatedAccount.Blocked -eq 'false') { $true } else { $false }
                Data             = $correlatedAccount
            }
        }
    }

    Write-Information 'Account data import completed'
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-PynterError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Pynter account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not create or correlate Pynter account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}