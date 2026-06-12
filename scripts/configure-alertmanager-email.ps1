t$ErrorActionPreference = "Stop"

$email = Read-Host "Gmail address used to send and receive the test alert"
$securePassword = Read-Host "Gmail App Password (input is hidden)" -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

try {
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

    $secret = @{
        apiVersion = "v1"
        kind = "Secret"
        metadata = @{
            name = "alertmanager-email"
            namespace = "monitoring"
        }
        type = "Opaque"
        stringData = @{
            password = $password
        }
    } | ConvertTo-Json -Depth 10

    $config = @{
        apiVersion = "monitoring.coreos.com/v1alpha1"
        kind = "AlertmanagerConfig"
        metadata = @{
            name = "email-test"
            namespace = "monitoring"
            labels = @{
                alertmanagerConfig = "email-test"
            }
        }
        spec = @{
            route = @{
                receiver = "gmail"
                groupWait = "10s"
                groupInterval = "1m"
                repeatInterval = "1h"
            }
            receivers = @(
                @{
                    name = "gmail"
                    emailConfigs = @(
                        @{
                            to = $email
                            from = $email
                            smarthost = "smtp.gmail.com:587"
                            authUsername = $email
                            authPassword = @{
                                name = "alertmanager-email"
                                key = "password"
                            }
                            requireTLS = $true
                            sendResolved = $true
                        }
                    )
                }
            )
        }
    } | ConvertTo-Json -Depth 20

    $secret | kubectl apply -f -
    $config | kubectl apply -f -

    Write-Host "Email receiver configured. Wait for EmailTestAlert to fire."
}
finally {
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    $password = $null
}
