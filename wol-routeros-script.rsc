# RouterOS Script for WOL Wake-on-LAN Manager
# This script periodically fetches pending WOL tasks from the Workers API and executes them

# Configuration
:global WOL_API_URL "https://your-worker-url.cloudflareworkers.com/api/wol/tasks"
:global INTERVAL 60s ; # Check every 60 seconds

# Main function
:global WOLManager {
    # Fetch pending WOL tasks from API
    :local response [/tool fetch url="$WOL_API_URL" method=get output=user as-value];
    :local status [:tostr ($response->"status")];
    
    # Check if request was successful
    if ($status = "200") {
        :local data [:tostr ($response->"data")];
        
        # Parse JSON response
        :local tasks [/system script environment get ("tasks")];
        :local parsedTasks [/system script environment parse $data];
        
        # Extract tasks array
        :local taskList [:pick $parsedTasks "{" "}" ];
        
        # Process each task
        :foreach task in=$taskList do={
            :local macAddress [/system script environment get ($task->"macAddress")];
            :local taskId [/system script environment get ($task->"id")];
            
            # Execute WOL wake up
            :log info "Sending WOL packet to $macAddress (Task ID: $taskId)";
            /tool wol mac=$macAddress interface=bridge ;
            
            # Update task status to processing
            :local updateUrl "$WOL_API_URL";
            :local updateData "{\"id\":\"$taskId\",\"status\":\"processing\"}";
            /tool fetch url="$updateUrl" method=put http-data=$updateData http-header-field="Content-Type: application/json" output=none;
            
            # Wait a moment for the device to wake up
            :delay 2s;
            
            # Check if device is responsive (ping test)
            :local pingResult [/ping $macAddress count=3 interval=1s as-value];
            :local packetsSent [:tostr ($pingResult->"sent")];
            :local packetsReceived [:tostr ($pingResult->"received")];
            
            :local finalStatus "failed";
            if ($packetsReceived > 0) {
                :set finalStatus "success";
                :log info "Device $macAddress woke up successfully (Task ID: $taskId)";
            } else {
                :log error "Failed to wake up device $macAddress (Task ID: $taskId)";
            }
            
            # Update final task status
            :local finalUpdateData "{\"id\":\"$taskId\",\"status\":\"$finalStatus\"}";
            /tool fetch url="$updateUrl" method=put http-data=$finalUpdateData http-header-field="Content-Type: application/json" output=none;
        }
    } else {
        :log error "Failed to fetch WOL tasks. Status: $status";
    }
}

# Create scheduler to run the script periodically
/system scheduler add name="WOL-Manager" interval=$INTERVAL on-event="$WOLManager" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-time=startup

# Initial run
$WOLManager;

:log info "WOL Manager script installed and running!";
