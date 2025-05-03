
function GetIncident($APIKey, $limit, $offset) {
    $uri = "https://api.pagerduty.com/incidents?limit=$limit&offset=$offset&sort_by=created_at:desc&time_zone=Asia/Tokyo"
    $headers=@{}
    $headers.Add("Accept", "application/json")
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Token token=$APIKey")
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
    return $response
}

function GetAlerts($APIKey,$incident_id, $limit, $offset) {
    $uri = "https://api.pagerduty.com/incidents/$incident_id/alerts?limit=$limit&offset=$offset"
    $headers=@{}
    $headers.Add("Accept", "application/json")
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Token token=$APIKey")
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
    return $response
}

function CheckIncident(){
    $limit = 10
    $offset = 0
    
    $result = GetIncident $APIKey $limit $offset
    $result | Convertto-json -Depth 10 | Out-File -FilePath "incident.json" -Encoding utf8

    $incidents = @()
    foreach ($incident in $result.incidents) {

        $status_map = @{
            "triggered" = "起票"
            "acknowledged" = "受付"
            "resolved" = "完了"
        }

        $incident_status = $status_map[$incident.status]

        # インシデントが解決済みになると、アサイン先が空になるため、解決済みのインシデントは最終更新者を表示
        if ($incident.status -eq "resolved") {
            $incident_assign = $incident.last_status_change_by.summary
        } else {
            $incident_assign = $incident.assignments[0].assignee.summary
        }

        $incidents += [PSCustomObject]@{
            連番 = $incident.incident_number
            集約 = $incident.alert_counts.all
            状況 = $incident_status
            緊急度 = $incident.urgency
            登録時刻 = $incident.created_at
            サービス名 = $incident.service.summary
            件名 = $incident.title
            インシデント内容 = $incident.summary
            アサイン先 = $incident_assign
            エスカレーションポリシー = $incident.escalation_policy.summary
            incident_id = $incident.id       
        }
    }
    

    return $incidents
}

function CheckAlertDetail($incidents, $checknubmber){
    # インシデントの詳細表示
    
    $checkincident = $incidents | Where-Object { $_.連番 -eq $checknumber }
    if ($checkincident) {
        $incident_id = $checkincident.incident_id
        $limit = 10
        $offset = 0
        $alerts = @()

        do {
            $alerts += GetAlerts $APIKey $incident_id $limit $offset
            $offset += $limit
        } while ($alerts.more -eq $true)

        #$alerts | Convertto-json -Depth 10 | Out-File -FilePath "alert.json" -Encoding utf8

        Write-Host ""
        Write-Host "インシデント番号: $($checkincident.連番) 集約: $($checkincident.集約)件 "

        $alert_count = 1
        foreach ($alert in $alerts.alerts) {
            Write-Host ""
            Write-Host "---$alert_count 件目---------------------------"
            Write-Host "件名: $($alert.body.cef_details.message)"
            Write-Host "発生時刻: $($alert.created_at)"
            Write-Host "アラート内容: $($alert.summary)"
            Write-Host "-----------------------------"
            $alert_count++
        }
    } else {
        Write-Host "指定された連番のインシデントは見つかりませんでした。"
    }
    Read-Host -Prompt "Enterを押すと戻ります"
}


# API Keyを環境変数から読み込む
$APIKey = $Args[0]

if (-not $APIKey) {
    Write-Host "API key not provided as an argument. Please enter it manually."
    $APIKey = Read-Host -Prompt
}

if (-not $APIKey) {
    Write-Error "API key is required."
    exit 1
}
    

do {
    $checknumber = ""
    $incidents = CheckIncident

    # 画面表示
    Clear-Host
    Write-Host ""
    Write-Host "--------------------------------------------------------------"
    Write-Host "PagerDuty インシデント一覧 $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") 時点 最新50件"
    Write-Host "--------------------------------------------------------------"
    $incidents |Sort-Object 連番 | Select-Object 連番,集約,状況,緊急度,登録時刻,サービス名,アサイン先,件名,インシデント内容,エスカレーションポリシー| Format-Table -AutoSize 

    Write-Host "インシデント一覧の更新`t: そのままEnter"
    Write-Host "インシデント詳細の確認`t: 確認するインシデントの連番を入力"
    Write-Host "GUIで一覧を表示`t`t: gui と入力"
    Write-Host "アプリの終了`t`t: exit と入力"

    $checknumber = Read-Host -Prompt "入力してね"

    if ($checknumber -eq "") {
        Continue
    } elseif ($checknumber -eq "exit") {
        Write-Host "終了します。"
        break
    } elseif ($checknumber -eq "gui") {
        $incidents |Sort-Object 連番 | Select-Object 連番,集約,状況,緊急度,登録時刻,サービス名,アサイン先,件名,インシデント内容,エスカレーションポリシー | Out-GridView
    } else {
        CheckAlertDetail $incidents $checknumber
    }
    # 1秒待機
    Start-Sleep -Seconds 1
} while ($True)