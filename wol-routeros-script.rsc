# RouterOS Script for WOL Wake-on-LAN Manager

:global WolTasksUrl "https://auto-wol.pages.dev/api/wol/tasks"
:global WolNotifyUrl "https://auto-wol.pages.dev/api/wol/tasks/notify"

:global WolInterface "ether1"

:local TempFileName "wol_tasks.json"

:if ([:len [/file find name=$TempFileName]] > 0) do={
    /file remove $TempFileName
}

:local fetchSuccess false
:local retryCount 0
:local maxRetries 3

:while ($fetchSuccess = false && $retryCount < $maxRetries) do={
    :do {
        /tool fetch url=($WolTasksUrl . "/pending") http-method=get dst-path=$TempFileName
        :set fetchSuccess true
    } on-error={
        :log warning ("WOL-Manager: Download failed. Attempt " . ($retryCount+1))
        :set retryCount ($retryCount + 1)
        :delay 3s
    }
}

:if ($fetchSuccess = false) do={
    :log error "WOL-Manager: Failed to download tasks file."
    :return
}

:delay 1s

:local fileId [/file find name=$TempFileName]
:if ([:len $fileId] = 0) do={
    :log error "WOL-Manager: File not found!"
    :return
}

:local fileContent [/file get $fileId contents]

:if ([:len $fileContent] = 0) do={
    :log info "WOL-Manager: No pending tasks."
    /file remove $TempFileName
    :return
}

:local payload
:do {
    :set payload [:deserialize from=json $fileContent]
} on-error={
    :log error "WOL-Manager: Invalid JSON in file."
    /file remove $TempFileName
    :return
}

/file remove $TempFileName

:local tasks ($payload->"tasks")

:if ([:len $tasks] = 0) do={
    :return
}

:foreach task in=$tasks do={
    :local macAddress ($task->"macAddress")
    :local taskId ($task->"id")
    
    :log info "WOL-Manager: Waking $macAddress (Task ID: $taskId)"
    
    :do {
        /tool wol mac=$macAddress interface=$WolInterface
    } on-error={
        :log error ("WOL-Manager: Interface " . $WolInterface . " not found! Check script settings.")
    }
    
    # Update Status: Processing
    :local procData "{\"id\":\"$taskId\",\"status\":\"processing\"}"
    :do {
        /tool fetch url=$WolTasksUrl http-method=put http-header-field="Content-Type: application/json" http-data=$procData output=none
    } on-error={ :log warning "WOL-Manager: Failed to update status to processing" }

    :local isOnline false
    :local attempts 0
    :local maxLoop 20
    
    :while ($attempts < $maxLoop && $isOnline = false) do={
        :set attempts ($attempts + 1)
        :delay 5s
        
        :local arpId [/ip arp find mac-address=$macAddress]
        
        :if ([:len $arpId] > 0) do={
            :local ipAddr [/ip arp get ($arpId->0) address]
            :local pingCount [/ping address=$ipAddr count=1 interval=0.5s]
            
            :if ($pingCount > 0) do={
                :set isOnline true
                :log info "WOL-Manager: Device $macAddress is ONLINE"
            }
        }
    }

    :if ($isOnline) do={
        :local succData "{\"id\":\"$taskId\",\"status\":\"success\"}"
        :do {
            /tool fetch url=$WolTasksUrl http-method=put http-header-field="Content-Type: application/json" http-data=$succData output=none
        } on-error={}
        
        :local notifyData "{\"id\":\"$taskId\"}"
        :do {
            /tool fetch url=$WolNotifyUrl http-method=post http-header-field="Content-Type: application/json" http-data=$notifyData output=none
        } on-error={}
        
    } else={
        :log warning "WOL-Manager: Wake failed for $macAddress"
        :local failData "{\"id\":\"$taskId\",\"status\":\"failed\"}"
        :do {
            /tool fetch url=$WolTasksUrl http-method=put http-header-field="Content-Type: application/json" http-data=$failData output=none
        } on-error={}
    }
}