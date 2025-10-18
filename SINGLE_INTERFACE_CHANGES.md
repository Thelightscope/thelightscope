# Single Interface Monitoring - Implementation Summary

## Overview
Modified LightScope to monitor only the interface with the most TCP traffic, rather than all interfaces simultaneously. This reduces resource usage and focuses monitoring on the most active network interface.

Additionally, implemented a 24-hour automatic restart mechanism to ensure the core process remains fresh and any accumulated state or memory is cleared regularly.

## Key Changes

### 1. New Discovery Functions

#### `discover_top_interface()` (Mac/Linux)
- **Location**: Lines 1906-1970 in `lightscope_core.py`
- **Purpose**: Polls each available interface for 10 seconds and returns the one with the most TCP packets
- **Uses**: `pylibpcap.base.Sniff` for packet capture

#### `discover_top_interface_windows()` (Windows)
- **Location**: Lines 1852-1918 in `lightscope_core.py`
- **Purpose**: Same as above but for Windows using the pcap library
- **Uses**: `pcap.pcap` for packet capture

### 2. Modified lightscope_run() - Mac/Linux Section

**Old Behavior** (Lines 2061-2136):
- Discovered all interfaces
- Spawned processes for ALL interfaces
- Monitored for changes and added/removed interfaces independently

**New Behavior** (Lines 2128-2208):
- Discovers all interfaces
- **Polls each interface to find the one with most traffic**
- **Spawns processes for ONLY the top interface**
- Tracks the active interface and its IPs
- On interface changes, **terminates ALL processes** and rediscovers

**Change Detection Logic**:
```python
needs_rediscovery = False

if active_interface not in new_mapping:
    # Active interface disappeared
    needs_rediscovery = True
elif new_mapping[active_interface] != active_ips:
    # Active interface IPs changed
    needs_rediscovery = True
elif set(new_mapping.keys()) != set(all_interfaces.keys()):
    # Interface list changed (new or removed interfaces)
    needs_rediscovery = True
```

### 3. Modified lightscope_run() - Windows Section

**Old Behavior** (Lines 2219-2294):
- Same multi-interface approach as Mac/Linux

**New Behavior** (Lines 2379-2453):
- Identical logic to Mac/Linux section but uses Windows-specific discovery function
- Only monitors ONE interface at a time

### 4. 24-Hour Automatic Restart

**Implementation**:
- **Mac/Linux**: Lines 2215-2236 in `lightscope_core.py`
- **Windows**: Lines 2397-2418 in `lightscope_core.py`

**How it works**:
1. Records `core_start_time` when the core starts
2. On each monitor loop iteration (every 60 seconds):
   - Calculates `elapsed_time = current_time - core_start_time`
   - If `elapsed_time >= 24 hours`:
     - Logs the restart reason with runtime duration
     - Terminates all 3 interface processes cleanly
     - Returns from `lightscope_run()`
3. The runner (`lightscope-runner.py`) detects the clean exit and automatically restarts the core

**Benefits**:
- Clears accumulated memory/state
- Ensures fresh start daily
- Prevents potential memory leaks from long-running processes
- Maintains consistent performance over time

**Log Output**:
```
LightScope core started at Mon Jan 15 10:30:00 2025, will restart after 24 hours
...
[+] 24-hour restart interval reached (running for 24.0 hours)
[+] Terminating interface processes for scheduled restart...
[+] All interface processes terminated. Exiting for scheduled restart.
```

## Thread Management

### Before Changes
- **Multiple interface threads**: Each interface had 3 processes:
  - `lightscope_process` (packet processing)
  - `read_from_interface_process` (packet capture)
  - `upload_process` (data upload)
- Total threads = `3 × number_of_interfaces`

### After Changes
- **Single interface threads**: Only 3 processes total:
  - `lightscope_process` (packet processing for top interface)
  - `read_from_interface_process` (packet capture for top interface)
  - `upload_process` (data upload for top interface)
- **Total threads = 3** (constant, regardless of number of interfaces)

### Thread Lifecycle
1. **Startup**: Discover top interface → Spawn 3 processes → Record start time
2. **Normal operation**: Monitor active interface
3. **Scheduled restart (every 24 hours)**:
   - Check elapsed time on each monitor loop
   - After 24 hours: Terminate all 3 processes
   - Exit cleanly → Runner automatically restarts core
   - New core instance goes through full startup again
4. **Interface change detected**: 
   - Terminate all 3 processes
   - Wait for clean shutdown (timeout=1s each)
   - Rediscover top interface
   - Spawn fresh 3 processes
5. **Update detected**: Terminate all processes and exit for runner restart

## Testing Recommendations

### Test Case 1: Single Interface System
- **Expected**: Should work exactly as before, just with discovery phase first

### Test Case 2: Multiple Interface System
- **Expected**: Should monitor only the interface with most TCP traffic
- **Verify**: Check that only one interface shows in logs

### Test Case 3: Interface Addition
- **Expected**: If a new interface with more traffic appears, should:
  1. Detect change in interface list
  2. Terminate existing processes
  3. Poll all interfaces again
  4. Switch to new top interface

### Test Case 4: Interface Removal
- **Expected**: If active interface goes away:
  1. Detect interface disappeared
  2. Terminate existing processes
  3. Poll remaining interfaces
  4. Select new top interface

### Test Case 5: IP Address Change
- **Expected**: If active interface IPs change:
  1. Detect IP change
  2. Terminate and rediscover
  3. May select same interface or different one based on traffic

### Test Case 6: 24-Hour Restart
- **Expected**: After running for 24 hours:
  1. Core logs "24-hour restart interval reached"
  2. All 3 processes terminate cleanly
  3. Runner automatically restarts the core
  4. Core goes through interface discovery again
- **Test with shortened interval**: For testing, temporarily change `restart_interval = 24 * 60 * 60` to `restart_interval = 60` (1 minute) to verify restart mechanism works

## Performance Impact

### Startup Time
- **Increased**: +10 seconds × number_of_interfaces
  - Example: 3 interfaces = +30 seconds startup time
- **Reason**: Need to poll each interface to determine which has most traffic

### Runtime Performance
- **Improved**: Reduced thread count
  - Before: 3 × N threads (where N = number of interfaces)
  - After: 3 threads (constant)
- **Memory**: Lower memory usage with fewer threads
- **CPU**: Lower CPU usage with focused monitoring

### Interface Change Performance
- **New overhead**: When interfaces change, must:
  - Terminate 3 processes
  - Poll all interfaces (10s each)
  - Spawn 3 new processes
- **Frequency**: Only happens when network configuration changes (rare)

## Configuration Changes

No configuration file changes required. All changes are internal to the code logic.

## Backward Compatibility

- **Fully backward compatible**: No API changes, no config changes
- **Behavior change**: Only monitors one interface instead of all
- **Log format**: Enhanced with discovery information

## Rollback Plan

If issues arise, revert these commits to restore multi-interface monitoring:
1. Remove `discover_top_interface()` and `discover_top_interface_windows()` functions
2. Restore original `lightscope_run()` sections (both Mac/Linux and Windows)
3. Original code maintained multi-interface monitoring with dynamic add/remove

## Future Enhancements

1. **Configurable poll duration**: Make the 10-second poll time configurable
2. **Smart switching**: Add hysteresis to prevent frequent interface switching
3. **Manual override**: Allow config file to specify which interface to monitor
4. **Parallel polling**: Poll all interfaces simultaneously instead of sequentially (reduce startup time)
5. **Traffic threshold**: Only switch interfaces if new one has significantly more traffic

