classdef MedDispenserApp < matlab.apps.AppBase

    % APPLICATION UI COMPONENTS MATRIX (GRAPHICAL INTERFACE HANDLES)
    properties (Access = public)
        UIFigure          matlab.ui.Figure

        % LOGIN SCREEN COMPONENTS
        LoginPanel        matlab.ui.container.Panel
        LogoImage         matlab.ui.control.Image
        AppTitleLabel     matlab.ui.control.Label
        SubtitleLabel     matlab.ui.control.Label
        UserLabel         matlab.ui.control.Label
        UserField         matlab.ui.control.EditField
        PassLabel         matlab.ui.control.Label
        PassField         matlab.ui.control.EditField
        LoginButton       matlab.ui.control.Button
        LoginErrorLabel   matlab.ui.control.Label

        % MAIN DASHBOARD CONTROL PERIPHERALS
        DashPanel         matlab.ui.container.Panel
        WelcomeLabel      matlab.ui.control.Label
        BtnScanLoad       matlab.ui.control.Button
        BtnLogout         matlab.ui.control.Button
        SerialStatusLabel matlab.ui.control.Label

        % LIVE EDGE TELEMETRY DISPLAY PANEL
        InventoryPanel    matlab.ui.container.Panel
        StockTitleLabel   matlab.ui.control.Label
        StockALabel       matlab.ui.control.Label
        StockBLabel       matlab.ui.control.Label
        LastActionLabel   matlab.ui.control.Label

        % OPTICAL SCAN & INTAKE RELOAD PANEL
        ScanPanel         matlab.ui.container.Panel
        SC_Title          matlab.ui.control.Label
        SC_CamLabel       matlab.ui.control.Label
        SC_Axes           matlab.ui.control.UIAxes
        SC_StartBtn       matlab.ui.control.Button
        SC_StopBtn        matlab.ui.control.Button
        SC_ComLbl         matlab.ui.control.Label
        SC_ComField       matlab.ui.control.EditField
        SC_RefreshBtn     matlab.ui.control.Button
        SC_ConnectBtn     matlab.ui.control.Button
        SC_DisconnectBtn  matlab.ui.control.Button
        SC_BarcodeLabel   matlab.ui.control.Label
        SC_CommandLabel   matlab.ui.control.Label
        SC_SendLabel      matlab.ui.control.Label
        SC_ReturnBtn      matlab.ui.control.Button
        SC_RecoveryBtn    matlab.ui.control.Button
    end

    % PRIVATE SYSTEM STATE ENGINE PROPERTIES
    properties (Access = private)
        CurrentUser   = ''  % Currently authenticated operator session ID
        LastUsedPort  = ''  % Cached active serial interface descriptor (e.g., 'COM3')

        SerialObj = []      % Active serialport object subsystem handle
        CamObj    = []      % Hardware webcam sensor capture handle
        CamTimer  = []      % Fixed-rate processing execution timer for frame analysis

        % Mock Authorization Matrix (SHA-256 placeholder concept, active pass PIN = 1234)
        AuthMatrix = struct(...
            'doctor', '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918', ...
            'nurse',  '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918', ...
            'admin',  '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918');
        AudioPlayerObj = [] % Audio buffer playback engine handle for system alerts
    end

    % PRIVATE CORE ENGINE CALLBACKS & PROCESSING LOGIC
    methods (Access = private)
        % Executes on app deployment. Initializes layout states and loads sound files.
        function startupFcn(app)
            showScreen(app, 'login'); % Lock view to gateway panel on boot
            try
                [y, fs] = audioread('mi_tren_cuidalo.mp3');
                app.AudioPlayerObj = audioplayer(y, fs);
            catch ME
                disp(['Warning: Telemetry audio alert source failed to load: ', ME.message]);
            end
        end

        % Centralized state machine router controlling panel UI visibility frames.
        function showScreen(app, screen)
            panels = {app.LoginPanel, app.DashPanel, app.ScanPanel};
            for k = 1:numel(panels)
                panels{k}.Visible = 'off';
            end
            switch screen
                case 'login', app.LoginPanel.Visible = 'on';
                case 'dash',  app.DashPanel.Visible  = 'on'; refreshDash(app);
                case 'scan',  app.ScanPanel.Visible  = 'on'; syncScanInterface(app);
            end
        end

        % Validates operator credentials matching local security keys matrix records.
        function LoginButtonPushed(app, ~)
            user = strtrim(app.UserField.Value);
            pass = app.PassField.Value;

            if isfield(app.AuthMatrix, user) && strcmp(pass, '1234')
                app.CurrentUser = user;
                app.LoginErrorLabel.Visible = 'off';
                app.UserField.Value  = '';
                app.PassField.Value  = '';
                showScreen(app, 'dash');
            end
        end

        function PassFieldValueChanged(app, ~)
            LoginButtonPushed(app, []);
        end

        % Refreshes main dashboard connectivity markers and layout metrics.
        function refreshDash(app)
            app.WelcomeLabel.Text = sprintf('User Session: %s', upper(app.CurrentUser));
            if isempty(app.SerialObj) || ~isvalid(app.SerialObj)
                app.SerialStatusLabel.Text      = 'STATUS: Edge Peripheral Disconnected';
                app.SerialStatusLabel.FontColor = [0.70 0.20 0.20]; % Warning Red
            else
                app.SerialStatusLabel.Text      = sprintf('STATUS: Online Serial Link [%s]', app.LastUsedPort);
                app.SerialStatusLabel.FontColor = [0.12 0.55 0.30]; % Operational Green
            end
        end

        % Auto-detects and synchronizes available hardware COM ports on menu deployment.
        function syncScanInterface(app)
            if isempty(app.LastUsedPort)
                availablePorts = serialportlist("available");
                if ~isempty(availablePorts)
                    app.LastUsedPort = availablePorts{1}; % Automatically target the first detected active COM port
                end
            end
            if ~isempty(app.LastUsedPort)
                app.SC_ComField.Value = app.LastUsedPort;
            end
        end

        % ASYNC SERIAL INTERRUPT CALLBACK: Fired automatically when an Edge token line arrives.
        % Parses incoming live inventory metrics streamed from the ESP32.
        function serialDataAvailable(app, src, ~)
            try
                if src.NumBytesAvailable > 0
                    rawString = strtrim(readline(src));
                    app.SC_SendLabel.Text = sprintf('Wired Rx [%s] -> %s', char(datetime('now','Format','HH:mm:ss')), rawString);

                    % Trigger acoustic alert indicator on edge activity events
                    if contains(rawString, 'RFID') || contains(rawString, 'STOCK_UPDATE:')
                        if ~isempty(app.AudioPlayerObj)
                            stop(app.AudioPlayerObj); % Dynamic audio buffer reset override
                            play(app.AudioPlayerObj);
                        end
                    end

                    % REGEX PAYLOAD PARSER: Extracts structured telemetry data tokens from the serial frame
                    if contains(rawString, 'STOCK_UPDATE:')
                        dataPayload = extractAfter(rawString, 'STOCK_UPDATE:');
                        tokens = regexp(dataPayload, 'MED_A\s*=\s*(?<medA>\d+),\s*MED_B\s*=\s*(?<medB>\d+)', 'names');
                        if ~isempty(tokens)
                            % Dynamically overwrite display text labels with verified counts
                            app.StockALabel.Text = sprintf('Compartment A (Med A): %s Units Loaded', tokens.medA);
                            app.StockBLabel.Text = sprintf('Compartment B (Med B): %s Units Loaded', tokens.medB);
                            app.LastActionLabel.Text = sprintf('Telemetry Refreshed: %s', char(datetime('now','Format','HH:mm:ss')));
                        end
                    elseif contains(rawString, 'ACK:')
                        app.LastActionLabel.Text = sprintf('Edge Response Received: %s', extractAfter(rawString, 'ACK:'));
                    end
                end
            catch ME
                app.LastActionLabel.Text = sprintf('Sync Telemetry Interrupted: %s', ME.message);
                app.SC_SendLabel.Text = sprintf('Rx Error: %s', ME.message);
            end
        end

        % DISASTER RECOVERY PIPELINE: Safely wipes crashed channels and builds a clean link state.
        function executeErrorRecovery(app)
            app.SC_SendLabel.Text = 'Executing system hardware pipeline recovery...';
            drawnow;

            % Step 1: Safe decomposition of damaged communication handle allocations
            if ~isempty(app.SerialObj)
                try delete(app.SerialObj); catch; end
                app.SerialObj = [];
            end

            % Step 2: Query OS hardware buses registry mapping
            availablePorts = serialportlist("available");
            if isempty(availablePorts)
                app.SC_SendLabel.Text = 'Recovery Aborted: No valid physical USB COM architecture detected.';
                uialert(app.UIFigure, 'Please check the physical USB wired link interface on the Edge Microcontroller.', 'Hardware Missing');
                return;
            end

            % Step 3: Hot-plug mapping reconnection routing engine pass
            try
                if any(strcmp(availablePorts, app.LastUsedPort))
                    targetPort = app.LastUsedPort;
                else
                    targetPort = availablePorts{1}; % Fallback default target choice
                end

                % Re-instantiate serial channel linking to ESP32 clock parameters
                app.SerialObj = serialport(targetPort, 115200, 'Timeout', 2);
                configureTerminator(app.SerialObj, 'LF');
                configureCallback(app.SerialObj, "terminator", @app.serialDataAvailable);
                app.LastUsedPort = targetPort;
                app.SC_ComField.Value = targetPort;
                app.SC_SendLabel.Text = sprintf('Recovery Success: Link safely restored on active port %s.', targetPort);
                refreshDash(app);
            catch ME
                app.SC_SendLabel.Text = sprintf('Recovery Failure: Re-routing execution crashed: %s', ME.message);
            end
        end

        % OPTICAL LIFECYCLE CONTROLLER: Safely de-allocates system camera threads.
        function stopCamera(app)
            try
                if ~isempty(app.CamTimer)
                    if isvalid(app.CamTimer) && strcmp(app.CamTimer.Running, 'on')
                        stop(app.CamTimer);
                    end
                    if isvalid(app.CamTimer), delete(app.CamTimer); end
                    app.CamTimer = [];
                end

                if ~isempty(app.CamObj)
                    app.CamObj = []; % Disconnect web-camera object reference handle
                end

                cla(app.SC_Axes); % Wipe graphics scene render buffers clear
                app.SC_CamLabel.Text  = 'Status: Optical Hardware Idle';
                app.SC_SendLabel.Text = 'Optical Scanning System: HALTED. Sensor released.';
                app.SC_StartBtn.Enable = 'on';
                app.SC_StopBtn.Enable  = 'off';
            catch ME
                app.SC_SendLabel.Text = sprintf('Sensor Halt Error: %s', ME.message);
            end
        end

        function BtnLogoutPushed(app, ~)
            app.stopCamera();
            showScreen(app, 'login');
        end

        function BtnScanLoadPushed(app, ~)
            showScreen(app,'scan');
        end
        
        function SC_ReturnBtnPushed(app, ~)
            app.stopCamera(); 
            showScreen(app,'dash');
        end

        % Scans and inventories structural USB COM ports mapped by the target machine OS.
        function SC_RefreshBtnPushed(app, ~)
            ports = serialportlist("available");
            if isempty(ports)
                app.SC_SendLabel.Text = sprintf('Port Scan: No serial ports detected.\nCheck USB cable / driver (CP210x or CH340).');
            else
                app.SC_SendLabel.Text = sprintf('Port Scan: Available -> %s', strjoin(ports, ', '));
                currentPort = strtrim(app.SC_ComField.Value);
                if isempty(currentPort) || ~any(strcmp(ports, currentPort))
                    app.SC_ComField.Value = ports{1};
                end
            end
        end

        % Locks a dedicated serial infrastructure pathway with the Edge microcontroller node.
        function SC_ConnectBtnPushed(app, ~)
            port = strtrim(app.SC_ComField.Value);
            if isempty(port)
                app.SC_SendLabel.Text = 'Error: State valid COM Port architecture.';
                return;
            end

            available = serialportlist("available");
            if ~any(strcmp(available, port))
                if isempty(available)
                    msg = sprintf(['Port "%s" not found. No serial ports are currently available.\n' ...
                        'Check that the ESP32 is plugged in via USB and that the CP210x/CH340 ' ...
                        'driver is installed, then press REFRESH PORTS.'], port);
                else
                    msg = sprintf(['Port "%s" not found or already in use by another program ' ...
                        '(e.g. Arduino IDE Serial Monitor).\nAvailable ports: %s'], port, strjoin(available, ', '));
                end
                app.SC_SendLabel.Text = msg;
                uialert(app.UIFigure, msg, 'Port Not Available');
                return;
            end

            try
                if ~isempty(app.SerialObj) && isvalid(app.SerialObj)
                    configureCallback(app.SerialObj, "terminator", []);
                    delete(app.SerialObj);
                    app.SerialObj = [];
                end

                % Instantiate data stream pipeline matching ESP32 firmware configuration limits
                app.SerialObj = serialport(port, 115200, 'Timeout', 2);
                configureTerminator(app.SerialObj, 'LF');
                configureCallback(app.SerialObj, "terminator", @app.serialDataAvailable);

                app.LastUsedPort = port;
                app.SC_SendLabel.Text = sprintf('Wired Link: Serial channel initialized on %s', port);
                refreshDash(app);
            catch ME
                app.SC_SendLabel.Text = sprintf('Link Failure: %s', ME.message);
                uialert(app.UIFigure, ME.message, 'Serial Connection Error');
            end
        end

        function SC_DisconnectBtnPushed(app, ~)
            if ~isempty(app.SerialObj) && isvalid(app.SerialObj)
                configureCallback(app.SerialObj, "terminator", []);
                delete(app.SerialObj);
                app.SerialObj = [];
                app.SC_SendLabel.Text = 'Wired Link: Serial channel disconnected.';
            else
                app.SC_SendLabel.Text = 'Wired Link: No active serial channel to disconnect.';
            end
            refreshDash(app);
        end

        % Boots up internal visual hardware webcam drivers and activates the background loop scheduler timer.
        function SC_StartBtnPushed(app, ~)
            try
                if isempty(app.CamObj)
                    app.SC_SendLabel.Text = 'Camera: Initializing local optical sensor... Please wait.';
                    drawnow;
                    app.CamObj = webcam(1); % Capture defaults path stream mapping handle
                end

                if isempty(app.CamTimer) || ~isvalid(app.CamTimer)
                    app.CamTimer = timer('ExecutionMode', 'fixedRate', ...
                                         'Period', 0.2, ... % 5Hz Frame Processing Rate (Every 200ms)
                                         'TimerFcn', @(~,~) cameraTick(app));
                end

                if strcmp(app.CamTimer.Running, 'off')
                    start(app.CamTimer);
                    app.SC_CamLabel.Text  = 'Status: Optical Hardware Active';
                    app.SC_SendLabel.Text = 'Optical Scanning System: ACTIVE (5Hz real-time refresh)';
                    app.SC_StartBtn.Enable = 'off';
                    app.SC_StopBtn.Enable  = 'on';
                else
                    app.SC_SendLabel.Text = 'Optical Scanning System: Already active and listening.';
                end
            catch ME
                app.SC_SendLabel.Text = sprintf('Camera initialization failed: %s. Check USB/Permissions.', ME.message);
            end
        end

        function SC_StopBtnPushed(app, ~)
            stopCamera(app);
        end

        % PERIODIC TICK LOOP (5Hz Thread Engine): Grabs frames, renders them on UI axes, 
        % decodes barcodes, and enforces non-blocking ingest rate limits.
        function cameraTick(app)
            try
                % Step 1: Capture snapshot array slice matrix from raw driver frame stream
                frame = snapshot(app.CamObj);

                % Step 2: Render image viewport layout inside App Designer axes node optimally
                hImg = findobj(app.SC_Axes, 'Type', 'image');
                if isempty(hImg)
                    imshow(frame, 'Parent', app.SC_Axes);
                end

                drawnow; % Flush UI graphics thread processing queue instantly

                % Step 3: Ingestion Image processing and translation decoders block execution pass
                barcodeText = '';
                try
                    [barcodeText, ~] = readBarcode(frame); % Computer Vision Toolbox lookup engine
                catch
                    try
                        barcodeText = qrcode_decode(rgb2gray(frame)); % Fallback structural QR algorithm path
                    catch
                        % Matrix matching pass failed on this execution loop instance
                    end
                end

                % Step 4: NON-BLOCKING COOLDOWN DEBOUNCE GATEGUARD (Blocks infinite recursive intake floods)
                if ~isempty(barcodeText) && strlength(string(barcodeText)) > 0

                    lastScanTime = getappdata(app.UIFigure, 'LastScanTime');
                    if isempty(lastScanTime)
                        lastScanTime = datetime('now') - seconds(10);
                    end

                    elapsedSeconds = seconds(datetime('now') - lastScanTime);
                    
                    % REFILL THROTTLE THRESHOLD: Hardcoded 3.0 seconds cooldown limit requirement per capsule
                    if elapsedSeconds >= 3.0
                        setappdata(app.UIFigure, 'LastScanTime', datetime('now'));
                        app.SC_BarcodeLabel.Text = sprintf('Barcode Captured: %s', barcodeText);
                        
                        cmd = barcodeToCommand(app, barcodeText);
                        app.SC_CommandLabel.Text = sprintf('Parsed Directive: %s', cmd);
                        
                        sendSerialCommand(app, cmd); % Dispatch structural inventory load token
                    else
                        remainingTime = ceil(3.0 - elapsedSeconds);
                        app.SC_SendLabel.Text = sprintf('Scan Locked: Wait %d s to clear camera...', remainingTime);
                    end
                end

            catch ME
                app.SC_CamLabel.Text = sprintf('Runtime Error: Optical stream dropped: %s', ME.message);
                stopCamera(app);
            end
        end


        % Evaluates incoming image text strings to derive structured micro-directives.
        function cmd = barcodeToCommand(~, barcodeText)
            if contains(upper(barcodeText),'MED_A') || contains(barcodeText,'1')
                cmd = 'LOAD_MED_1';
            elseif contains(upper(barcodeText),'MED_B') || contains(barcodeText,'2')
                cmd = 'LOAD_MED_2';
            else
                cmd = sprintf('LOAD_%s', upper(strtrim(barcodeText)));
            end
        end


        % Transmits raw textual control strings down across the operational USB UART wire
        function sendSerialCommand(app, cmd)
            if isempty(app.SerialObj) || ~isvalid(app.SerialObj)
                app.SC_SendLabel.Text = sprintf('Pipeline Error: Interface connection lost.\nInitializing automated recovery...');
                executeErrorRecovery(app);
                if isempty(app.SerialObj), return; end
            end
            try
                writeline(app.SerialObj, cmd);
                app.SC_SendLabel.Text = sprintf('Wired Tx Success [%s] -> %s', char(datetime('now','Format','HH:mm:ss')), cmd);
                if ~isempty(app.AudioPlayerObj)
                    stop(app.AudioPlayerObj);
                    play(app.AudioPlayerObj);
                end
            catch ME
                app.SC_SendLabel.Text = sprintf('Transmission crash trapped: %s. Please hit Manual Recovery.', ME.message);
            end
        end
    end

    % PRIVATE GUI STYLING ENGINE (AUTO-GENERATED COMPONENT ARCHITECTURE)
    methods (Access = private)

        function createComponents(app)
            W = 780;
            H = 560;

            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.Position  = [80 80 W H];
            app.UIFigure.Name      = 'MedDispenser | Pharmacy Intake Frontend Station';
            app.UIFigure.Color     = [1.00 1.00 1.00];

            function p = mkPanel(parent, pos, title)
                p = uipanel(parent);
                p.Position = pos; p.Title = title;
                p.BackgroundColor = [1.00 1.00 1.00]; p.ForegroundColor = [0.20 0.20 0.20];
                p.FontSize = 12; p.FontWeight = 'bold'; p.Visible = 'off';
            end

            % INITIALIZE LOGIN CANVAS GRID COMPONENTS
            app.LoginPanel = mkPanel(app.UIFigure, [0 0 W H], '');
            app.LoginPanel.BackgroundColor = [1.00 1.00 1.00];
            app.LoginPanel.BorderType = 'none';

            app.LogoImage = uiimage(app.LoginPanel);
            app.LogoImage.Position = [315 420 150 75];
            app.LogoImage.ImageSource = 'Screenshot 2026-06-05 073343.png';
            app.LogoImage.HorizontalAlignment = 'center';

            app.AppTitleLabel = uilabel(app.LoginPanel);
            app.AppTitleLabel.Text = 'MED DISPENSER SYSTEM';
            app.AppTitleLabel.FontSize = 22; app.AppTitleLabel.FontWeight = 'bold';
            app.AppTitleLabel.FontColor = [0.12 0.45 0.74]; app.AppTitleLabel.HorizontalAlignment = 'center';
            app.AppTitleLabel.Position = [190 365 400 35];

            app.SubtitleLabel = uilabel(app.LoginPanel);
            app.SubtitleLabel.Text = 'Hospital Ward & Pharmacy Station Interface Module';
            app.SubtitleLabel.FontSize = 12; app.SubtitleLabel.FontColor = [0.20 0.20 0.20];
            app.SubtitleLabel.HorizontalAlignment = 'center'; app.SubtitleLabel.Position = [140 335 500 25];

            loginCard = uipanel(app.LoginPanel);
            loginCard.Position = [265 130 250 190]; loginCard.BackgroundColor = [0.97 0.98 0.99];
            
            app.UserLabel = uilabel(loginCard); app.UserLabel.Text = 'Operator ID';
            app.UserLabel.FontSize = 11; app.UserLabel.FontWeight = 'bold'; app.UserLabel.FontColor = [0.15 0.15 0.15];
            app.UserLabel.Position = [20 138 100 22];

            app.UserField = uieditfield(loginCard,'text'); app.UserField.Position = [20 112 210 26];
            app.UserField.Placeholder = 'doctor / nurse / admin'; app.UserField.BackgroundColor = [1.00 1.00 1.00];

            app.PassLabel = uilabel(loginCard); app.PassLabel.Text = 'Secure Access Pin';
            app.PassLabel.FontSize = 11; app.PassLabel.FontWeight = 'bold'; app.PassLabel.FontColor = [0.15 0.15 0.15]; 
            app.PassLabel.Position = [20 81 120 22];

            app.PassField = uieditfield(loginCard,'text'); app.PassField.Position = [20 55 210 26];
            app.PassField.Placeholder = 'Required password'; app.PassField.BackgroundColor = [1.00 1.00 1.00];
            app.PassField.ValueChangedFcn = createCallbackFcn(app, @PassFieldValueChanged, true);
            
            app.LoginButton = uibutton(loginCard,'push'); app.LoginButton.Text = 'AUTHENTICATE';
            app.LoginButton.Position = [20 15 210 32]; app.LoginButton.FontWeight = 'bold';
            app.LoginButton.BackgroundColor = [0.12 0.45 0.74]; app.LoginButton.FontColor = [1 1 1];
            app.LoginButton.ButtonPushedFcn = createCallbackFcn(app, @LoginButtonPushed, true);

            app.LoginErrorLabel = uilabel(app.LoginPanel); app.LoginErrorLabel.Text = '';
            app.LoginErrorLabel.FontColor = [0.70 0.20 0.20]; app.LoginErrorLabel.HorizontalAlignment = 'center';
            app.LoginErrorLabel.Position = [190 95 400 22]; app.LoginErrorLabel.Visible = 'off';

            % INITIALIZE WORKSPACE DASHBOARD CANVAS PERIPHERALS
            app.DashPanel = mkPanel(app.UIFigure, [0 0 W H], '');
            app.DashPanel.BackgroundColor = [1.00 1.00 1.00]; app.DashPanel.BorderType = 'none';

            topBar = uipanel(app.DashPanel); topBar.Position = [0 500 W 60];
            topBar.BackgroundColor = [0.12 0.45 0.74]; topBar.BorderType = 'none';

            app.WelcomeLabel = uilabel(topBar); app.WelcomeLabel.Text = 'Active Session';
            app.WelcomeLabel.FontSize = 15; app.WelcomeLabel.FontColor = [1 1 1]; app.WelcomeLabel.FontWeight = 'bold'; 
            app.WelcomeLabel.Position = [20 15 400 30];

            app.BtnLogout = uibutton(topBar,'push'); app.BtnLogout.Text = 'DISCONNECT';
            app.BtnLogout.Position = [650 15 110 28]; app.BtnLogout.BackgroundColor = [1.00 1.00 1.00];
            app.BtnLogout.FontColor = [0.70 0.20 0.20]; app.BtnLogout.FontWeight = 'bold';
            app.BtnLogout.ButtonPushedFcn = createCallbackFcn(app, @BtnLogoutPushed, true);

            app.SerialStatusLabel = uilabel(app.DashPanel); app.SerialStatusLabel.Text = 'STATUS: Edge Peripheral Disconnected';
            app.SerialStatusLabel.FontSize = 11; app.SerialStatusLabel.FontWeight = 'bold';
            app.SerialStatusLabel.FontColor = [0.15 0.15 0.15]; app.SerialStatusLabel.Position = [25 470 450 20];

            scanCard = uipanel(app.DashPanel); scanCard.Position = [30 65 340 395];
            scanCard.BackgroundColor = [0.97 0.98 0.99]; scanCard.BorderType = 'line';

            scLbl = uilabel(scanCard); scLbl.Text = 'Inventory Scanner Module';
            scLbl.FontSize = 15; scLbl.FontWeight = 'bold'; scLbl.FontColor = [0.12 0.45 0.74]; scLbl.Position = [20 345 300 30];

            scDesc = uilabel(scanCard);
            scDesc.Text = sprintf(['Open the camera scanner to read medication barcodes and ' ...
                'automatically dispatch the matching reload command (LOAD_MED_1 or ' ...
                'LOAD_MED_2) to the ESP32 dispenser over the serial link.\n\n' ...
                'Make sure the controller link is established before scanning, so each ' ...
                'successful scan updates the live stock telemetry shown on this dashboard.']);
            scDesc.FontSize = 12; scDesc.FontColor = [0.25 0.25 0.25]; scDesc.WordWrap = 'on'; scDesc.Position = [20 70 300 260];

            app.BtnScanLoad = uibutton(scanCard,'push'); app.BtnScanLoad.Text = 'OPEN SCANNER MODULE';
            app.BtnScanLoad.Position = [20 20 300 36]; app.BtnScanLoad.FontWeight = 'bold';
            app.BtnScanLoad.BackgroundColor = [0.12 0.45 0.74]; app.BtnScanLoad.FontColor = [1 1 1];
            app.BtnScanLoad.ButtonPushedFcn = createCallbackFcn(app, @BtnScanLoadPushed, true);

            % LIVE REAL-TIME TELEMETRY PANEL LAYOUT BUILD
            app.InventoryPanel = uipanel(app.DashPanel); app.InventoryPanel.Position = [410 65 340 395];
            app.InventoryPanel.BackgroundColor = [0.95 0.97 1.00]; app.InventoryPanel.BorderType = 'line';

            app.StockTitleLabel = uilabel(app.InventoryPanel); app.StockTitleLabel.Text = 'EDGE NODE TELEMETRY';
            app.StockTitleLabel.FontSize = 14; app.StockTitleLabel.FontWeight = 'bold';
            app.StockTitleLabel.FontColor = [0.12 0.45 0.74]; app.StockTitleLabel.Position = [20 345 300 30];

            app.StockALabel = uilabel(app.InventoryPanel); app.StockALabel.Text = 'Compartment A (Med A): Sync Pending...';
            app.StockALabel.FontSize = 13; app.StockALabel.FontColor = [0.15 0.15 0.15]; app.StockALabel.Position = [20 290 300 26];

            app.StockBLabel = uilabel(app.InventoryPanel); app.StockBLabel.Text = 'Compartment B (Med B): Sync Pending...';
            app.StockBLabel.FontSize = 13; app.StockBLabel.FontColor = [0.15 0.15 0.15]; app.StockBLabel.Position = [20 250 300 26];

            logBox = uipanel(app.InventoryPanel); logBox.Title = 'Edge Pipeline Log'; logBox.Position = [20 30 300 200];
            logBox.BackgroundColor = [1.00 1.00 1.00]; logBox.FontWeight = 'bold'; logBox.ForegroundColor = [0.20 0.20 0.20];

            app.LastActionLabel = uilabel(logBox); app.LastActionLabel.Text = 'Edge Bus Pipeline Status: Idle';
            app.LastActionLabel.Position = [10 10 280 165]; app.LastActionLabel.FontSize = 11;
            app.LastActionLabel.FontColor = [0.15 0.15 0.15]; app.LastActionLabel.WordWrap = 'on'; app.LastActionLabel.VerticalAlignment = 'top';

            % INITIALIZE OPTICAL CONTROL LAYOUT SUBMODULES
            app.ScanPanel = mkPanel(app.UIFigure, [0 0 W H], 'Optical Automation Module Interface');
            app.SC_Title = uilabel(app.ScanPanel);
            app.SC_Title.Text = 'Barcode Scanner: capture medication barcodes and dispatch reload commands to the ESP32';
            app.SC_Title.FontSize = 12; app.SC_Title.FontColor = [0.12 0.45 0.74]; app.SC_Title.Position = [15 510 700 22];

            app.SC_Axes = uiaxes(app.ScanPanel); app.SC_Axes.Position = [15 200 470 295];
            app.SC_Axes.XTick = []; app.SC_Axes.YTick = []; title(app.SC_Axes, 'Optical Sensor Live Capture Stream');

            app.SC_CamLabel = uilabel(app.ScanPanel); app.SC_CamLabel.Text = 'Status: Optical Hardware Idle';
            app.SC_CamLabel.FontSize = 11; app.SC_CamLabel.FontColor = [0.15 0.15 0.15]; app.SC_CamLabel.Position = [15 178 300 18];
            
            app.SC_StartBtn = uibutton(app.ScanPanel,'push'); app.SC_StartBtn.Text = 'START SENSOR';
            app.SC_StartBtn.Position = [15 145 140 30]; app.SC_StartBtn.BackgroundColor = [0.12 0.45 0.74];
            app.SC_StartBtn.FontColor = [1 1 1]; app.SC_StartBtn.FontWeight = 'bold';
            app.SC_StartBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_StartBtnPushed, true);

            app.SC_StopBtn = uibutton(app.ScanPanel,'push'); app.SC_StopBtn.Text = 'STOP SENSOR';
            app.SC_StopBtn.Position = [165 145 140 30]; app.SC_StopBtn.BackgroundColor = [1.00 1.00 1.00];
            app.SC_StopBtn.FontColor = [0.70 0.20 0.20]; app.SC_StopBtn.FontWeight = 'bold'; app.SC_StopBtn.Enable = 'off';
            app.SC_StopBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_StopBtnPushed, true);

            serialBox = uipanel(app.ScanPanel); serialBox.Title = 'Hardware Pipeline Link (ESP32 Controller)';
            serialBox.Position = [500 330 260 160]; serialBox.BackgroundColor = [0.97 0.98 0.99];
            serialBox.FontWeight = 'bold'; serialBox.ForegroundColor = [0.20 0.20 0.20];
            
            app.SC_ComLbl = uilabel(serialBox); app.SC_ComLbl.Text = 'COM Port:';
            app.SC_ComLbl.FontSize = 11; app.SC_ComLbl.FontWeight = 'bold'; app.SC_ComLbl.FontColor = [0.15 0.15 0.15];
            app.SC_ComLbl.Position = [10 110 90 22];

            app.SC_ComField = uieditfield(serialBox,'text'); app.SC_ComField.Position = [105 108 140 24];
            app.SC_ComField.Placeholder = 'COM3'; app.SC_ComField.BackgroundColor = [1.00 1.00 1.00];

            app.SC_RefreshBtn = uibutton(serialBox,'push'); app.SC_RefreshBtn.Text = 'REFRESH PORTS';
            app.SC_RefreshBtn.Position = [10 35 240 28]; app.SC_RefreshBtn.FontWeight = 'bold';
            app.SC_RefreshBtn.BackgroundColor = [1.00 1.00 1.00]; app.SC_RefreshBtn.FontColor = [0.12 0.45 0.74];
            app.SC_RefreshBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_RefreshBtnPushed, true);
            
            app.SC_ConnectBtn = uibutton(serialBox,'push'); app.SC_ConnectBtn.Text = 'LINK INTERFACE';
            app.SC_ConnectBtn.Position = [10 70 115 28]; app.SC_ConnectBtn.FontWeight = 'bold';
            app.SC_ConnectBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_ConnectBtnPushed, true);

            app.SC_DisconnectBtn = uibutton(serialBox,'push'); app.SC_DisconnectBtn.Text = 'DROP LINK';
            app.SC_DisconnectBtn.Position = [135 70 115 28]; app.SC_DisconnectBtn.FontWeight = 'bold';
            app.SC_DisconnectBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_DisconnectBtnPushed, true);

            infoBox = uipanel(app.ScanPanel); infoBox.Title = 'Decoded Stream Telemetry';
            infoBox.Position = [500 150 260 170]; infoBox.BackgroundColor = [0.97 0.98 0.99];
            infoBox.FontWeight = 'bold'; infoBox.ForegroundColor = [0.20 0.20 0.20];
            
            app.SC_BarcodeLabel = uilabel(infoBox); app.SC_BarcodeLabel.Text = 'Barcode Matrix: Null';
            app.SC_BarcodeLabel.WordWrap = 'on'; app.SC_BarcodeLabel.FontColor = [0.15 0.15 0.15]; app.SC_BarcodeLabel.Position = [8 110 240 28];

            app.SC_CommandLabel = uilabel(infoBox); app.SC_CommandLabel.Text = 'Parsed Core Directive: Null';
            app.SC_CommandLabel.WordWrap = 'on'; app.SC_CommandLabel.FontColor = [0.15 0.15 0.15]; app.SC_CommandLabel.Position = [8 75 240 28];

            app.SC_SendLabel = uilabel(infoBox); app.SC_SendLabel.Text = 'Serial Channel Activity Log: Null';
            app.SC_SendLabel.WordWrap = 'on'; app.SC_SendLabel.FontSize = 10; app.SC_SendLabel.FontColor = [0.15 0.15 0.15];
            app.SC_SendLabel.Position = [8 10 240 56];

            app.SC_RecoveryBtn = uibutton(app.ScanPanel, 'push'); app.SC_RecoveryBtn.Text = 'FORCE HARDWARE PIPELINE RECOVERY';
            app.SC_RecoveryBtn.Position = [500 100 260 30]; app.SC_RecoveryBtn.BackgroundColor = [0.98 0.92 0.92];
            app.SC_RecoveryBtn.FontColor = [0.70 0.20 0.20]; app.SC_RecoveryBtn.FontWeight = 'bold';
            app.SC_RecoveryBtn.ButtonPushedFcn = @(~,~) executeErrorRecovery(app);

            app.SC_ReturnBtn = uibutton(app.ScanPanel,'push'); app.SC_ReturnBtn.Text = 'RETURN';
            app.SC_ReturnBtn.Position = [W-120 15 100 28]; app.SC_ReturnBtn.BackgroundColor = [1.00 1.00 1.00];
            app.SC_ReturnBtn.FontColor = [0.15 0.15 0.15];
            app.SC_ReturnBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_ReturnBtnPushed, true);

            app.UIFigure.Visible = 'on';
        end
    end

    % PUBLIC APP LIFECYCLE MANAGEMENT SUBMODULES
    methods (Access = public)

        function app = MedDispenserApp
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0, clear app; end
        end

        function delete(app)
            stopCamera(app); % Clean sensor locks on destroy pass
            if ~isempty(app.SerialObj) && isvalid(app.SerialObj)
                delete(app.SerialObj);
            end
            delete(app.UIFigure)
        end
    end
end