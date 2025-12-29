{#
 # Copyright (c) 2025 Eric Kapitanski <e@alumni.usc.edu>
 # University of Southern California Information Sciences Institute
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        var data_get_map = {'frm_GeneralSettings': '/api/lightscope/settings/get'};

        // Load settings and status
        mapDataToFormUI(data_get_map).done(function(data) {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
            refreshAll();
        });

        // Refresh all status info
        function refreshAll() {
            updateServiceStatus();
            updateDashboardInfo();
            updateLogs();
        }

        // Auto-refresh every 10 seconds
        setInterval(refreshAll, 10000);

        // Update service status display
        function updateServiceStatus() {
            ajaxCall('/api/lightscope/status/status', {}, function(data, status) {
                if (data && data.status) {
                    if (data.status === 'running') {
                        $('#service_status').removeClass('text-danger').addClass('text-success');
                        $('#service_status').html('<i class="fa fa-check-circle"></i> Running');
                        $('#btn_start').prop('disabled', true);
                        $('#btn_stop').prop('disabled', false);
                    } else {
                        $('#service_status').removeClass('text-success').addClass('text-danger');
                        $('#service_status').html('<i class="fa fa-times-circle"></i> Stopped');
                        $('#btn_start').prop('disabled', false);
                        $('#btn_stop').prop('disabled', true);
                    }
                    if (data.process_count) {
                        $('#process_count').text(data.process_count);
                    }
                }
            });
        }

        // Update dashboard info from status API
        function updateDashboardInfo() {
            ajaxCall('/api/lightscope/status/status', {}, function(data, status) {
                if (data) {
                    if (data.dashboard_url) {
                        $('#dashboard_link').attr('href', data.dashboard_url);
                        $('#dashboard_link').html('<i class="fa fa-external-link"></i> ' + data.dashboard_url);
                        $('#dashboard_container').show();
                    } else {
                        $('#dashboard_container').hide();
                    }
                    if (data.database) {
                        $('#database_id').text(data.database);
                        $('#database_container').show();
                    }
                }
            });
        }

        // Update logs
        function updateLogs() {
            ajaxCall('/api/lightscope/status/logs', {}, function(data, status) {
                if (data && data.logs) {
                    $('#log_content').text(data.logs);
                    // Auto-scroll to bottom
                    var logBox = document.getElementById('log_content');
                    logBox.scrollTop = logBox.scrollHeight;
                }
            });
        }

        // Save settings
        $('#btn_save').click(function() {
            saveFormToEndpoint('/api/lightscope/settings/set', 'frm_GeneralSettings', function() {
                $('#btn_save_progress').addClass('fa fa-spinner fa-pulse');
                $.post('/api/lightscope/service/reconfigure', {}, function(data) {
                    $('#btn_save_progress').removeClass('fa fa-spinner fa-pulse');
                    setTimeout(refreshAll, 1000);
                });
            });
        });

        // Start service
        $('#btn_start').click(function() {
            $('#btn_start_progress').addClass('fa fa-spinner fa-pulse');
            $.post('/api/lightscope/service/start', {}, function(data) {
                $('#btn_start_progress').removeClass('fa fa-spinner fa-pulse');
                setTimeout(refreshAll, 2000);
            });
        });

        // Stop service
        $('#btn_stop').click(function() {
            $('#btn_stop_progress').addClass('fa fa-spinner fa-pulse');
            $.post('/api/lightscope/service/stop', {}, function(data) {
                $('#btn_stop_progress').removeClass('fa fa-spinner fa-pulse');
                setTimeout(refreshAll, 1000);
            });
        });

        // Restart service
        $('#btn_restart').click(function() {
            $('#btn_restart_progress').addClass('fa fa-spinner fa-pulse');
            $.post('/api/lightscope/service/restart', {}, function(data) {
                $('#btn_restart_progress').removeClass('fa fa-spinner fa-pulse');
                setTimeout(refreshAll, 2000);
            });
        });

        // Refresh logs button
        $('#btn_refresh_logs').click(function() {
            updateLogs();
        });
    });
</script>

<div class="content-box">
    <div class="content-box-header">
        <h3><i class="fa fa-shield"></i> LightScope Cybersecurity Research Honeypot and Telescope</h3>
    </div>
    <div class="content-box-main">
        <!-- Status Section -->
        <div class="row">
            <div class="col-md-12">
                <table class="table table-condensed">
                    <tbody>
                        <tr>
                            <td style="width: 150px;"><strong>{{ lang._('Service Status') }}</strong></td>
                            <td id="service_status" class="text-muted">
                                <i class="fa fa-spinner fa-pulse"></i> {{ lang._('Loading...') }}
                            </td>
                        </tr>
                        <tr id="dashboard_container" style="display: none;">
                            <td><strong>{{ lang._('Dashboard') }}</strong></td>
                            <td>
                                <a id="dashboard_link" href="#" target="_blank" class="btn btn-xs btn-primary">
                                    <i class="fa fa-external-link"></i> {{ lang._('Loading...') }}
                                </a>
                            </td>
                        </tr>
                        <tr id="database_container" style="display: none;">
                            <td><strong>{{ lang._('Database ID') }}</strong></td>
                            <td><code id="database_id">-</code></td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>

        <hr/>

        <!-- Settings Form -->
        {{ partial("layout_partials/base_form", ['fields': settings, 'id': 'frm_GeneralSettings']) }}

        <hr/>

        <!-- Action Buttons -->
        <div class="row">
            <div class="col-md-12">
                <button class="btn btn-primary" id="btn_save" type="button">
                    <i id="btn_save_progress" class=""></i>
                    <b>{{ lang._('Save') }}</b>
                </button>
                <button class="btn btn-success" id="btn_start" type="button">
                    <i id="btn_start_progress" class=""></i>
                    {{ lang._('Start') }}
                </button>
                <button class="btn btn-danger" id="btn_stop" type="button">
                    <i id="btn_stop_progress" class=""></i>
                    {{ lang._('Stop') }}
                </button>
                <button class="btn btn-warning" id="btn_restart" type="button">
                    <i id="btn_restart_progress" class=""></i>
                    {{ lang._('Restart') }}
                </button>
            </div>
        </div>

        <hr/>

        <!-- Logs Section -->
        <div class="row">
            <div class="col-md-12">
                <h4>
                    <i class="fa fa-file-text-o"></i> {{ lang._('Service Logs') }}
                    <button class="btn btn-xs btn-default" id="btn_refresh_logs" type="button">
                        <i class="fa fa-refresh"></i>
                    </button>
                </h4>
                <pre id="log_content" style="height: 300px; overflow-y: scroll; background: #1e1e1e; color: #d4d4d4; padding: 10px; font-size: 12px;">Loading logs...</pre>
            </div>
        </div>
    </div>
</div>
