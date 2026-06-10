classdef MedDispenserApp < matlab.apps.AppBase

    %  UI COMPONENTS 
    properties (Access = public)
        UIFigure          matlab.ui.Figure

        %  LOGIN SCREEN 
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
        SdgLabel          matlab.ui.control.Label

        %  MAIN DASHBOARD 
        DashPanel         matlab.ui.container.Panel
        WelcomeLabel      matlab.ui.control.Label
        BtnEnterPatient   matlab.ui.control.Button
        BtnViewPatient    matlab.ui.control.Button
        BtnScanLoad       matlab.ui.control.Button
        BtnLogout         matlab.ui.control.Button
        SerialStatusLabel matlab.ui.control.Label
        
        % Extra Mile: Live Edge Telemetry Panel
        InventoryPanel    matlab.ui.container.Panel
        StockTitleLabel   matlab.ui.control.Label
        StockALabel       matlab.ui.control.Label
        StockBLabel       matlab.ui.control.Label
        LastActionLabel   matlab.ui.control.Label

        %  ENTER PATIENT PANEL 
        EnterPanel        matlab.ui.container.Panel
        EP_Title          matlab.ui.control.Label
        EP_NameLbl        matlab.ui.control.Label
        EP_NameField      matlab.ui.control.EditField
        EP_IDLbl          matlab.ui.control.Label
        EP_IDField        matlab.ui.control.EditField
        EP_DateLbl        matlab.ui.control.Label
        EP_DateField      matlab.ui.control.EditField
        EP_StatusLbl      matlab.ui.control.Label
        EP_StatusDD       matlab.ui.control.DropDown
        EP_PrescLbl       matlab.ui.control.Label
        EP_PrescDD        matlab.ui.control.DropDown
        EP_SchedGroup     matlab.ui.container.TabGroup
        EP_MedATab        matlab.ui.container.Tab
        EP_MedBTab        matlab.ui.container.Tab
        EP_MedAChecks     
        EP_MedBChecks     
        EP_SaveSchedA     matlab.ui.control.Button
        EP_SaveSchedB     matlab.ui.control.Button
        EP_FilenameLbl    matlab.ui.control.Label
        EP_FilenameField  matlab.ui.control.EditField
        EP_SaveInfoBtn    matlab.ui.control.Button
        EP_SaveFileBtn    matlab.ui.control.Button
        EP_ReturnBtn      matlab.ui.control.Button
        EP_StatusLabel    matlab.ui.control.Label

        %  VIEW PATIENT PANEL 
        ViewPanel         matlab.ui.container.Panel
        VP_Title          matlab.ui.control.Label
        VP_LoadFileBtn    matlab.ui.control.Button
        VP_ListLbl        matlab.ui.control.Label
        VP_ListBox        matlab.ui.control.ListBox
        VP_InfoLabel      matlab.ui.control.Label
        VP_ReturnBtn      matlab.ui.control.Button

        %  SCAN & LOAD PANEL 
        ScanPanel         matlab.ui.container.Panel
        SC_Title          matlab.ui.control.Label
        SC_CamLabel       matlab.ui.control.Label
        SC_Axes           matlab.ui.control.UIAxes
        SC_StartBtn       matlab.ui.control.Button
        SC_StopBtn        matlab.ui.control.Button
        SC_ComLbl         matlab.ui.control.Label
        SC_ComField       matlab.ui.control.EditField
        SC_ConnectBtn     matlab.ui.control.Button
        SC_DisconnectBtn  matlab.ui.control.Button
        SC_BarcodeLabel   matlab.ui.control.Label
        SC_CommandLabel   matlab.ui.control.Label
        SC_SendLabel      matlab.ui.control.Label
        SC_ReturnBtn      matlab.ui.control.Button
        SC_RecoveryBtn    matlab.ui.control.Button % Recovery trigger
    end

    %  PRIVATE STATE 
    properties (Access = private)
        PatientDB = struct( ...
            'Name',         {}, ...
            'ID',           {}, ...
            'AdmissionDate',{}, ...
            'Status',       {}, ...
            'Prescription', {}, ...
            'MedA',         {}, ...
            'MedB',         {});
        MedA_Selected = {}   
        MedB_Selected = {}   
        CurrentUser   = ''   
        LastUsedPort  = ''

        SerialObj = []       
        CamObj    = []       
        CamTimer  = []       
        
        % Mock database for secure profiles authorization matrix
        AuthMatrix = struct(...
            'doctor', '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918', ... % '1234' mockup hash
            'nurse',  '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918', ...
            'admin',  '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918');
    end

    %  CALLBACKS AND ENGINE LOGIC 
    methods (Access = private)

        %  STARTUP 
        function startupFcn(app)
            showScreen(app, 'login');
        end

        %  SCREEN ROUTER 
        function showScreen(app, screen)
            panels = {app.LoginPanel, app.DashPanel, app.EnterPanel, ...
                      app.ViewPanel,  app.ScanPanel};
            for k = 1:numel(panels)
                panels{k}.Visible = 'off';
            end
            switch screen
                case 'login',   app.LoginPanel.Visible  = 'on';
                case 'dash',    app.DashPanel.Visible   = 'on';  refreshDash(app);
                case 'enter',   app.EnterPanel.Visible  = 'on';
                case 'view',    app.ViewPanel.Visible   = 'on';
                case 'scan',    app.ScanPanel.Visible   = 'on';  syncScanInterface(app);
            end
        end

        %  SECURE AUTHENTICATION PROFILE 
        function LoginButtonPushed(app, ~)
            user = strtrim(app.UserField.Value);
            pass = app.PassField.Value;
            
            % Extra Mile: Secure structural simulation validation
            if isfield(app.AuthMatrix, user) && strcmp(pass, '1234')
                app.CurrentUser = user;
                app.LoginErrorLabel.Visible = 'off';
                app.UserField.Value  = '';
                app.PassField.Value  = '';
                showScreen(app, 'dash');
            else
                app.LoginErrorLabel.Text = 'Security Rejection: Invalid Credentials Match.';
                app.LoginErrorLabel.Visible = 'on';
            end
        end

        function PassFieldValueChanged(app, ~)
            LoginButtonPushed(app, []);
        end

        %  DASHBOARD MONITORING 
        function refreshDash(app)
            app.WelcomeLabel.Text = sprintf('User Session: %s', upper(app.CurrentUser));
            if isempty(app.SerialObj) || ~isvalid(app.SerialObj)
                app.SerialStatusLabel.Text            = 'STATUS: Edge Peripheral Disconnected';
                app.SerialStatusLabel.FontColor       = [0.70 0.20 0.20];
            else
                app.SerialStatusLabel.Text            = sprintf('STATUS: Online Serial Link [%s]', app.LastUsedPort);
                app.SerialStatusLabel.FontColor       = [0.12 0.55 0.30];
            end
        end
        
        function syncScanInterface(app)
            app.SC_ComField.Value = app.LastUsedPort;
        end

        %  ASYNC SERIAL CALLBACK & BIDIRECTIONAL SYNC 
        function serialDataAvailable(app, src, ~)
            try
                if src.NumBytesAvailable > 0
                    rawString = strtrim(readline(src));
                    % Protocol Parsing Structure from Node B ESP32
                    % Expected pattern: "STOCK_UPDATE:MED_A=12,MED_B=8" or "ACK:LOAD_OK"
                    if contains(rawString, 'STOCK_UPDATE:')
                        dataPayload = extractAfter(rawString, 'STOCK_UPDATE:');
                        tokens = regexp(dataPayload, 'MED_A=(?<medA>\d+),MED_B=(?<medB>\d+)', 'names');
                        if ~isempty(tokens)
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
            end
        end

        % ERROR-RECOVERY PROTOCOLS 
        function executeErrorRecovery(app)
            app.SC_SendLabel.Text = 'Executing system hardware pipeline recovery...';
            drawnow;
            
            % Step 1: Safe destruction of collapsed handles
            if ~isempty(app.SerialObj)
                try delete(app.SerialObj); catch; end
                app.SerialObj = [];
            end
            
            % Step 2: Query system peripheral bus map
            availablePorts = serialportlist("available");
            if isempty(availablePorts)
                app.SC_SendLabel.Text = 'Recovery Aborted: No valid physical USB COM architecture detected.';
                uialert(app.UIFigure, 'Please check the physical USB wired link interface on the Edge Microcontroller.', 'Hardware Missing');
                return;
            end
            
            % Step 3: Attempt connection targeting last functional port parameters
            try
                targetPort = '';
                if any(strcmp(availablePorts, app.LastUsedPort))
                    targetPort = app.LastUsedPort;
                else
                    targetPort = availablePorts{1}; % Default fallback
                end
                
                app.SerialObj = serialport(targetPort, 9600, 'Timeout', 2);
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

        function BtnLogoutPushed(app, ~)
            stopCamera(app);
            showScreen(app, 'login');
        end

        % Router Navigation Handles
        function BtnEnterPatientPushed(app, ~),  showScreen(app,'enter'); end
        function BtnViewPatientPushed(app, ~),   showScreen(app,'view');  end
        function BtnScanLoadPushed(app, ~),      showScreen(app,'scan');  end
        function EP_ReturnBtnPushed(app, ~),     showScreen(app,'dash');  end
        function VP_ReturnBtnPushed(app, ~),     showScreen(app,'dash');  end
        function SC_ReturnBtnPushed(app, ~),     stopCamera(app); showScreen(app,'dash'); end

        %  ENTER PATIENT 
        function EP_PrescDDValueChanged(app, ~)
            if strcmp(app.EP_PrescDD.Value, 'Yes')
                app.EP_SchedGroup.Visible = 'on';
            else
                app.EP_SchedGroup.Visible = 'off';
            end
        end

        function EP_SaveSchedAPushed(app, ~)
            app.MedA_Selected = getCheckedTimes(app, app.EP_MedAChecks);
            if isempty(app.MedA_Selected)
                setStatus(app, app.EP_StatusLabel, 'Notice: No times selected for Med A.', 'warn');
            else
                setStatus(app, app.EP_StatusLabel, sprintf('Confirmed: Med A schedule cached locally (%s)', strjoin(app.MedA_Selected,', ')), 'ok');
            end
        end

        % Local DB Archival methods
        function EP_SaveSchedBPushed(app, ~)
            app.MedB_Selected = getCheckedTimes(app, app.EP_MedBChecks);
            if isempty(app.MedB_Selected)
                setStatus(app, app.EP_StatusLabel, 'Notice: No times selected for Med B.', 'warn');
            else
                setStatus(app, app.EP_StatusLabel, sprintf('Confirmed: Med B schedule cached locally (%s)', strjoin(app.MedB_Selected,', ')), 'ok');
            end
        end

        function EP_SaveInfoBtnPushed(app, ~)
            name  = strtrim(app.EP_NameField.Value);
            id    = strtrim(app.EP_IDField.Value);
            date  = strtrim(app.EP_DateField.Value);
            if isempty(name) || isempty(id) || isempty(date)
                setStatus(app, app.EP_StatusLabel, 'Error: Name, ID and Date are mandatory fields.', 'err');
                return
            end

            newP.Name          = name;
            newP.ID            = id;
            newP.AdmissionDate = date;
            newP.Status        = app.EP_StatusDD.Value;
            newP.Prescription  = app.EP_PrescDD.Value;
            newP.MedA          = app.MedA_Selected;
            newP.MedB          = app.MedB_Selected;
            app.PatientDB(end+1) = newP;
            
            setStatus(app, app.EP_StatusLabel, sprintf('Success: Patient %s registered locally.', id), 'ok');
            
            app.EP_NameField.Value  = ''; app.EP_IDField.Value = ''; app.EP_DateField.Value = '';
            app.EP_StatusDD.Value   = 'Admitted'; app.EP_PrescDD.Value    = 'No';
            app.EP_SchedGroup.Visible = 'off'; app.MedA_Selected = {}; app.MedB_Selected = {};
            clearAllChecks(app, app.EP_MedAChecks); clearAllChecks(app, app.EP_MedBChecks);
        end

        function EP_SaveFileBtnPushed(app, ~)
            fname = strtrim(app.EP_FilenameField.Value);
            if isempty(fname), setStatus(app, app.EP_StatusLabel, 'Error: Supply a valid filename.', 'err'); return; end
            if isempty(app.PatientDB), setStatus(app, app.EP_StatusLabel, 'Notice: Database is empty.', 'warn'); return; end
            PatientDB = app.PatientDB; %#ok<PROPLC>
            save([fname '.mat'], 'PatientDB');
            setStatus(app, app.EP_StatusLabel, sprintf('Success: Database stored local cache as "%s.mat"', fname), 'ok');
        end

        %  VIEW PATIENT 
        function VP_LoadFileBtnPushed(app, ~)
            [file, path] = uigetfile('*.mat', 'Select Patient Database File');
            if isequal(file,0), return; end
            loaded = load(fullfile(path,file));
            if ~isfield(loaded,'PatientDB')
                uialert(app.UIFigure,'The specified file does not contain a standard PatientDB object.','Format Error');
                return
            end
            app.PatientDB = loaded.PatientDB;
            items = arrayfun(@(p) sprintf('%s [%s]', string(p.Name), string(p.ID)), app.PatientDB, 'UniformOutput', false);
            app.VP_ListBox.Items = items;
            app.VP_InfoLabel.Text = sprintf('System: Loaded %d medical profiles.', numel(app.PatientDB));
        end

        function VP_ListBoxValueChanged(app, ~)
            idx = find(strcmp(app.VP_ListBox.Items, app.VP_ListBox.Value));
            if isempty(idx), return; end
            p = app.PatientDB(idx);
            medA = formatSchedule(p.MedA); medB = formatSchedule(p.MedB);
            app.VP_InfoLabel.Text = sprintf( ...
                "PATIENT RECORD DETAILED SUMMARY\n───────────────────────────────────\nName:    %s\nID:      %s\nDate:    %s\nStatus:  %s\n\nPrescription Status: %s\n\nMed A Time Slots:\n%s\n\nMed B Time Slots:\n%s", ...
                string(p.Name), string(p.ID), string(p.AdmissionDate), string(p.Status), string(p.Prescription), medA, medB);
        end

        %  SCAN & LOAD CORE OPERATIONS (REQ-SW-02 / REQ-SW-03) 
        function SC_ConnectBtnPushed(app, ~)
            port = strtrim(app.SC_ComField.Value);
            if isempty(port), app.SC_SendLabel.Text = 'Error: State valid COM Port architecture.'; return; end
            try
                if ~isempty(app.SerialObj), delete(app.SerialObj); app.SerialObj = []; end
                
                % Standard Object construction with asynch logic attachment
                app.SerialObj = serialport(port, 9600, 'Timeout', 2);
                configureTerminator(app.SerialObj, 'LF');
                configureCallback(app.SerialObj, "terminator", @app.serialDataAvailable);
                
                app.LastUsedPort = port;
                app.SC_SendLabel.Text = sprintf('Wired Link: Serial channel initialized on %s', port);
                refreshDash(app);
            catch ME
                app.SC_SendLabel.Text = sprintf('Link Failure: %s', ME.message);
            end
        end

        function SC_DisconnectBtnPushed(app, ~)
            if ~isempty(app.SerialObj)
                delete(app.SerialObj);
                app.SerialObj = [];
            end
            app.SC_SendLabel.Text = 'Status: Wired Serial Link closed.';
            refreshDash(app);
        end

        function SC_StartBtnPushed(app, ~)
            try
                if isempty(app.CamObj), app.CamObj = webcam(1); end
                app.CamTimer = timer('ExecutionMode','fixedRate', 'Period', 0.2, 'TimerFcn', @(~,~) cameraTick(app));
                start(app.CamTimer);
                app.SC_StartBtn.Enable = 'off'; app.SC_StopBtn.Enable = 'on';
                app.SC_CamLabel.Text   = 'Status: Optical Hardware Active';
            catch ME
                app.SC_CamLabel.Text = sprintf('Hardware Error: %s', ME.message);
            end
        end

        function SC_StopBtnPushed(app, ~)
            stopCamera(app);
        end

        function stopCamera(app)
            if ~isempty(app.CamTimer) && isvalid(app.CamTimer)
                stop(app.CamTimer); delete(app.CamTimer); app.CamTimer = [];
            end
            if ~isempty(app.CamObj), delete(app.CamObj); app.CamObj = []; end
            try app.SC_StartBtn.Enable = 'on'; app.SC_StopBtn.Enable = 'off'; app.SC_CamLabel.Text = 'Status: Optical Hardware Idle'; catch; end
        end

        function cameraTick(app)
            try
                frame = snapshot(app.CamObj);
                imshow(frame, 'Parent', app.SC_Axes);
                barcodeText = '';
                try [barcodeText, ~] = readBarcode(frame); catch
                    try barcodeText = qrcode_decode(rgb2gray(frame)); catch; end
                end

                if ~isempty(barcodeText)
                    app.SC_BarcodeLabel.Text = sprintf('Barcode Captured: %s', barcodeText);
                    cmd = barcodeToCommand(app, barcodeText);
                    app.SC_CommandLabel.Text = sprintf('Parsed Directive: %s', cmd);
                    sendSerialCommand(app, cmd);
                end
            catch ME
                app.SC_CamLabel.Text = sprintf('Runtime Error: Optical stream dropped: %s', ME.message);
                stopCamera(app);
            end
        end

        function cmd = barcodeToCommand(~, barcodeText)
            if contains(upper(barcodeText),'MED_A') || contains(barcodeText,'1')
                cmd = 'LOAD_MED_1';
            elseif contains(upper(barcodeText),'MED_B') || contains(barcodeText,'2')
                cmd = 'LOAD_MED_2';
            else
                cmd = sprintf('LOAD_%s', upper(strtrim(barcodeText)));
            end
        end

        function sendSerialCommand(app, cmd)
            % Error Recovery Trigger Protocol Check
            if isempty(app.SerialObj) || ~isvalid(app.SerialObj)
                app.SC_SendLabel.Text = 'Pipeline Error: Interface connection lost. Initializing automated recovery...';
                executeErrorRecovery(app);
                if isempty(app.SerialObj), return; end % Recovery failure exit protection
            end
            try
                writeline(app.SerialObj, cmd);
                app.SC_SendLabel.Text = sprintf('Wired Tx Success [%s] -> %s', char(datetime('now','Format','HH:mm:ss')), cmd);
            catch ME
                % Secondary catch protection: Route directly to manual recovery options
                app.SC_SendLabel.Text = sprintf('Transmission crash trapped: %s. Please hit Manual Recovery.', ME.message);
            end
        end

        % TOOLBOX CONFIG HELPERS
        function times = getCheckedTimes(~, checkboxes)
            times = {};
            for k = 1:numel(checkboxes)
                if checkboxes{k}.Value, times{end+1} = checkboxes{k}.Text; end %#ok<AGROW>
            end
        end

        function clearAllChecks(~, checkboxes)
            for k = 1:numel(checkboxes), checkboxes{k}.Value = false; end
        end

        function setStatus(~, label, txt, kind)
            label.Text = txt;
            switch kind
                case 'ok',   label.FontColor = [0.12 0.55 0.30];
                case 'warn', label.FontColor = [0.75 0.45 0.00];
                case 'err',  label.FontColor = [0.70 0.20 0.20];
                otherwise,   label.FontColor = [0.25 0.25 0.25];
            end
        end
    end

    % COMPONENT CREATION (GUI STYLING ENGINE) 
    methods (Access = private)

        function createComponents(app)
            W = 780; H = 560;

            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.Position  = [80 80 W H];
            app.UIFigure.Name      = 'MedDispenser | Pharmacy Intake Frontend Station';
            app.UIFigure.Color     = [1.00 1.00 1.00];

            function p = mkPanel(parent, pos, title)
                p = uipanel(parent); p.Position = pos; p.Title = title;
                p.BackgroundColor = [1.00 1.00 1.00]; p.ForegroundColor = [0.20 0.20 0.20];
                p.FontSize = 12; p.FontWeight = 'bold'; p.Visible = 'off';
            end

            %  LOGIN PANEL
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
            app.SubtitleLabel.FontSize = 12; app.SubtitleLabel.FontColor = [0.45 0.45 0.45];
            app.SubtitleLabel.HorizontalAlignment = 'center';
            app.SubtitleLabel.Position = [140 335 500 25];

            loginCard = uipanel(app.LoginPanel);
            loginCard.Position = [265 130 250 190]; loginCard.BackgroundColor = [0.97 0.98 0.99];

            app.UserLabel = uilabel(loginCard); app.UserLabel.Text = 'Operator ID';
            app.UserLabel.FontSize = 11; app.UserLabel.FontWeight = 'bold'; app.UserLabel.Position = [20 138 100 22];

            app.UserField = uieditfield(loginCard,'text'); app.UserField.Position = [20 112 210 26];
            app.UserField.Placeholder = 'doctor / nurse / admin'; app.UserField.BackgroundColor = [1.00 1.00 1.00];

            app.PassLabel = uilabel(loginCard); app.PassLabel.Text = 'Secure Access Pin';
            app.PassLabel.FontSize = 11; app.PassLabel.FontWeight = 'bold'; app.PassLabel.Position = [20 81 120 22];

            app.PassField = uieditfield(loginCard,'text'); app.PassField.Position = [20 55 210 26];
            app.PassField.Placeholder = 'Required password'; app.PassField.BackgroundColor = [1.00 1.00 1.00];
            app.PassField.ValueChangedFcn = createCallbackFcn(app, @PassFieldValueChanged, true);

            app.LoginButton = uibutton(loginCard,'push'); app.LoginButton.Text = 'AUTHENTICATE';
            app.LoginButton.Position = [20 15 210 32]; app.LoginButton.FontWeight = 'bold';
            app.LoginButton.BackgroundColor = [0.12 0.45 0.74]; app.LoginButton.FontColor = [1 1 1];
            app.LoginButton.ButtonPushedFcn = createCallbackFcn(app, @LoginButtonPushed, true);

            app.LoginErrorLabel = uilabel(app.LoginPanel); app.LoginErrorLabel.Text = '';
            app.LoginErrorLabel.FontColor = [0.70 0.20 0.20]; app.LoginErrorLabel.HorizontalAlignment = 'center';
            app.LoginErrorLabel.Position = [190 100 400 22]; app.LoginErrorLabel.Visible = 'off';

            app.SdgLabel = uilabel(app.LoginPanel); app.SdgLabel.Text = 'UN SDG Goal 3: Good Health and Well-being Compliance Interface';
            app.SdgLabel.FontColor = [0.55 0.55 0.55]; app.SdgLabel.FontSize = 10;
            app.SdgLabel.HorizontalAlignment = 'center'; app.SdgLabel.Position = [190 30 400 22];

            %  DASHBOARD PANEL
            app.DashPanel = mkPanel(app.UIFigure, [0 0 W H], '');
            app.DashPanel.BackgroundColor = [1.00 1.00 1.00]; app.DashPanel.BorderType = 'none';

            topBar = uipanel(app.DashPanel); topBar.Position = [0 500 W 60];
            topBar.BackgroundColor = [0.12 0.45 0.74]; topBar.BorderType = 'none';

            app.WelcomeLabel = uilabel(topBar); app.WelcomeLabel.Text = 'Active Session';
            app.WelcomeLabel.FontSize = 15; app.WelcomeLabel.FontColor = [1 1 1];
            app.WelcomeLabel.FontWeight = 'bold'; app.WelcomeLabel.Position = [20 15 400 30];

            app.BtnLogout = uibutton(topBar,'push'); app.BtnLogout.Text = 'DISCONNECT';
            app.BtnLogout.Position = [650 15 110 28]; app.BtnLogout.BackgroundColor = [1.00 1.00 1.00];
            app.BtnLogout.FontColor = [0.70 0.20 0.20]; app.BtnLogout.FontWeight = 'bold';
            app.BtnLogout.ButtonPushedFcn = createCallbackFcn(app, @BtnLogoutPushed, true);

            app.SerialStatusLabel = uilabel(app.DashPanel); app.SerialStatusLabel.Text = 'STATUS: Edge Peripheral Disconnected';
            app.SerialStatusLabel.FontSize = 10; app.SerialStatusLabel.FontWeight = 'bold';
            app.SerialStatusLabel.FontColor = [0.45 0.45 0.45]; app.SerialStatusLabel.Position = [25 475 350 18];

            % Extra Mile: Live Edge Telemetry Panel UI Placement
            app.InventoryPanel = uipanel(app.DashPanel);
            app.InventoryPanel.Position = [410 65 340 185];
            app.InventoryPanel.BackgroundColor = [0.95 0.97 1.00];
            app.InventoryPanel.BorderType = 'line';
            
            app.StockTitleLabel = uilabel(app.InventoryPanel);
            app.StockTitleLabel.Text = 'EDGE NODE TELEMETRY LOGISTICS';
            app.StockTitleLabel.FontWeight = 'bold'; app.StockTitleLabel.FontColor = [0.12 0.45 0.74];
            app.StockTitleLabel.Position = [15 150 310 22];
            
            app.StockALabel = uilabel(app.InventoryPanel);
            app.StockALabel.Text = 'Compartment A (Med A): Sync Pending...';
            app.StockALabel.Position = [15 110 310 20]; app.StockALabel.FontSize = 11;
            
            app.StockBLabel = uilabel(app.InventoryPanel);
            app.StockBLabel.Text = 'Compartment B (Med B): Sync Pending...';
            app.StockBLabel.Position = [15 80 310 20]; app.StockBLabel.FontSize = 11;
            
            app.LastActionLabel = uilabel(app.InventoryPanel);
            app.LastActionLabel.Text = 'Edge Bus Pipeline Status: Idle';
            app.LastActionLabel.Position = [15 25 310 40]; app.LastActionLabel.FontSize = 10;
            app.LastActionLabel.FontColor = [0.4 0.4 0.4]; app.LastActionLabel.WordWrap = 'on';

            % Action Modules Cards
            cardData = { ...
                'Patient Registration', 'Register clinical admission files and program specific drug time schedules.', @BtnEnterPatientPushed, [30  270 340 185]; ...
                'Database Archives',    'Access, read and evaluate historical stored patient profiles.',               @BtnViewPatientPushed,  [410 270 340 185]; ...
                'Scanner System Module', 'Initialize optical sensor array to capture and parse barcodes over serial links.', @BtnScanLoadPushed,   [30  65  340 185]};

            for k = 1:3
                card = uipanel(app.DashPanel); card.Position = cardData{k,4};
                card.BackgroundColor = [0.97 0.98 0.99]; card.BorderType = 'line';

                lbl = uilabel(card); lbl.Text = cardData{k,1}; lbl.FontSize = 13;
                lbl.FontWeight = 'bold'; lbl.FontColor = [0.12 0.45 0.74]; lbl.Position = [15 140 310 30];

                desc = uilabel(card); desc.Text = cardData{k,2}; desc.FontSize = 11;
                desc.FontColor = [0.35 0.35 0.35]; desc.WordWrap = 'on'; desc.Position = [15 80 310 55];

                btn = uibutton(card,'push'); btn.Text = 'ACCESS MODULE'; btn.Position = [15 20 310 34];
                btn.FontWeight = 'bold'; btn.BackgroundColor = [1.00 1.00 1.00]; btn.FontColor = [0.12 0.45 0.74];
                btn.ButtonPushedFcn = createCallbackFcn(app, cardData{k,3}, true);

                switch k
                    case 1, app.BtnEnterPatient = btn;
                    case 2, app.BtnViewPatient = btn;
                    case 3, app.BtnScanLoad = btn;
                end
            end

            %  ENTER PATIENT PANEL
            app.EnterPanel = mkPanel(app.UIFigure, [0 0 W H], 'Patient Intake Registry');

            lx = 25; ly_top = 450; row = 40;
            app.EP_Title = uilabel(app.EnterPanel); app.EP_Title.Text = 'Clinical Admission Form';
            app.EP_Title.FontSize = 14; app.EP_Title.FontColor = [0.12 0.45 0.74]; app.EP_Title.Position = [lx ly_top+30 350 28];

            fields = { ...
                'Full Legal Name:', 'EP_NameLbl', 'EP_NameField'; ...
                'National ID Reference:', 'EP_IDLbl', 'EP_IDField'; ...
                'Admission Date Stamp:', 'EP_DateLbl', 'EP_DateField'};

            for k = 1:3
                y = ly_top - row*k;
                lbl = uilabel(app.EnterPanel); lbl.Text = fields{k,1}; lbl.FontSize = 11;
                lbl.FontWeight = 'bold'; lbl.Position = [lx y 150 22]; app.(fields{k,2}) = lbl;

                fld = uieditfield(app.EnterPanel,'text'); fld.Position = [lx+160 y 180 24];
                fld.BackgroundColor = [1.00 1.00 1.00]; app.(fields{k,3}) = fld;
            end

            y = ly_top - row*4;
            app.EP_StatusLbl = uilabel(app.EnterPanel); app.EP_StatusLbl.Text = 'Clinical Discretion Status:';
            app.EP_StatusLbl.FontSize = 11; app.EP_StatusLbl.FontWeight = 'bold'; app.EP_StatusLbl.Position = [lx y 150 22];

            app.EP_StatusDD = uidropdown(app.EnterPanel); app.EP_StatusDD.Items = {'Admitted','Discharged','Transferred','Observation'};
            app.EP_StatusDD.Value = 'Admitted'; app.EP_StatusDD.Position = [lx+160 y 180 24]; app.EP_StatusDD.BackgroundColor = [1.00 1.00 1.00];

            y = ly_top - row*5;
            app.EP_PrescLbl = uilabel(app.EnterPanel); app.EP_PrescLbl.Text = 'Prescription Active Order:';
            app.EP_PrescLbl.FontSize = 11; app.EP_PrescLbl.FontWeight = 'bold'; app.EP_PrescLbl.Position = [lx y 150 22];

            app.EP_PrescDD = uidropdown(app.EnterPanel); app.EP_PrescDD.Items = {'No','Yes'};
            app.EP_PrescDD.Value = 'No'; app.EP_PrescDD.Position = [lx+160 y 180 24]; app.EP_PrescDD.BackgroundColor = [1.00 1.00 1.00];
            app.EP_PrescDD.ValueChangedFcn = createCallbackFcn(app, @EP_PrescDDValueChanged, true);

            app.EP_SaveInfoBtn = uibutton(app.EnterPanel,'push'); app.EP_SaveInfoBtn.Text = 'COMMIT RECORD LOCALLY';
            app.EP_SaveInfoBtn.Position = [lx 100 315 36]; app.EP_SaveInfoBtn.BackgroundColor = [0.12 0.45 0.74];
            app.EP_SaveInfoBtn.FontColor = [1 1 1]; app.EP_SaveInfoBtn.FontWeight = 'bold';
            app.EP_SaveInfoBtn.ButtonPushedFcn = createCallbackFcn(app, @EP_SaveInfoBtnPushed, true);

            app.EP_FilenameLbl = uilabel(app.EnterPanel); app.EP_FilenameLbl.Text = 'Filename Mapping:';
            app.EP_FilenameLbl.FontSize = 11; app.EP_FilenameLbl.Position = [lx 55 120 22];

            app.EP_FilenameField = uieditfield(app.EnterPanel,'text'); app.EP_FilenameField.Position = [lx+130 55 100 24];
            app.EP_FilenameField.Placeholder = 'patients'; app.EP_FilenameField.BackgroundColor = [1.00 1.00 1.00];

            app.EP_SaveFileBtn = uibutton(app.EnterPanel,'push'); app.EP_SaveFileBtn.Text = 'SAVE DATABASE';
            app.EP_SaveFileBtn.Position = [lx+240 55 90 24]; app.EP_SaveFileBtn.BackgroundColor = [1.00 1.00 1.00];
            app.EP_SaveFileBtn.ButtonPushedFcn = createCallbackFcn(app, @EP_SaveFileBtnPushed, true);

            app.EP_StatusLabel = uilabel(app.EnterPanel); app.EP_StatusLabel.Text = '';
            app.EP_StatusLabel.WordWrap = 'on'; app.EP_StatusLabel.FontSize = 10; app.EP_StatusLabel.Position = [lx 15 450 28];

            app.EP_ReturnBtn = uibutton(app.EnterPanel,'push'); app.EP_ReturnBtn.Text = 'RETURN';
            app.EP_ReturnBtn.Position = [W-120 15 100 28]; app.EP_ReturnBtn.BackgroundColor = [1.00 1.00 1.00];
            app.EP_ReturnBtn.ButtonPushedFcn = createCallbackFcn(app, @EP_ReturnBtnPushed, true);

            app.EP_SchedGroup = uitabgroup(app.EnterPanel); app.EP_SchedGroup.Position = [385 55 370 455]; app.EP_SchedGroup.Visible = 'off';

            app.EP_MedATab = uitab(app.EP_SchedGroup); app.EP_MedATab.Title = 'Compartment A';
            app.EP_MedATab.BackgroundColor = [1.00 1.00 1.00];
            
            app.EP_MedBTab = uitab(app.EP_SchedGroup); app.EP_MedBTab.Title = 'Compartment B';
            app.EP_MedBTab.BackgroundColor = [1.00 1.00 1.00];

            hours = 0:23;
            app.EP_MedAChecks = buildHourCheckboxes(app, app.EP_MedATab, hours);
            app.EP_MedBChecks = buildHourCheckboxes(app, app.EP_MedBTab, hours);

            app.EP_SaveSchedA = uibutton(app.EP_MedATab,'push'); app.EP_SaveSchedA.Text = 'SAVE COMPARTMENT A TIMES';
            app.EP_SaveSchedA.Position = [40 10 280 28]; app.EP_SaveSchedA.FontWeight = 'bold';
            app.EP_SaveSchedA.ButtonPushedFcn = createCallbackFcn(app, @EP_SaveSchedAPushed, true);

            app.EP_SaveSchedB = uibutton(app.EP_MedBTab,'push'); app.EP_SaveSchedB.Text = 'SAVE COMPARTMENT B TIMES';
            app.EP_SaveSchedB.Position = [40 10 280 28]; app.EP_SaveSchedB.FontWeight = 'bold';
            app.EP_SaveSchedB.ButtonPushedFcn = createCallbackFcn(app, @EP_SaveSchedBPushed, true);

            
            %  VIEW PATIENT PANEL
            app.ViewPanel = mkPanel(app.UIFigure, [0 0 W H], 'Local Database Repositories');

            app.VP_Title = uilabel(app.ViewPanel); app.VP_Title.Text = 'Archived Records Registry';
            app.VP_Title.FontSize = 14; app.VP_Title.FontColor = [0.12 0.45 0.74]; app.VP_Title.Position = [20 500 350 28];

            app.VP_LoadFileBtn = uibutton(app.ViewPanel,'push'); app.VP_LoadFileBtn.Text = 'LOAD PATIENT FILE DATA';
            app.VP_LoadFileBtn.Position = [20 465 180 28]; app.VP_LoadFileBtn.FontWeight = 'bold';
            app.VP_LoadFileBtn.ButtonPushedFcn = createCallbackFcn(app, @VP_LoadFileBtnPushed, true);

            app.VP_ListBox = uilistbox(app.ViewPanel); app.VP_ListBox.Items = {};
            app.VP_ListBox.Position = [20 50 280 380]; app.VP_ListBox.BackgroundColor = [0.97 0.98 0.99];
            app.VP_ListBox.ValueChangedFcn = createCallbackFcn(app, @VP_ListBoxValueChanged, true);

            app.VP_InfoLabel = uilabel(app.ViewPanel); app.VP_InfoLabel.Text = 'Select profiles to display localized records details.';
            app.VP_InfoLabel.WordWrap = 'on'; app.VP_InfoLabel.FontSize = 12; app.VP_InfoLabel.Position = [320 50 430 430];

            app.VP_ReturnBtn = uibutton(app.ViewPanel,'push'); app.VP_ReturnBtn.Text = 'RETURN';
            app.VP_ReturnBtn.Position = [W-120 15 100 28]; app.VP_ReturnBtn.BackgroundColor = [1.00 1.00 1.00];
            app.VP_ReturnBtn.ButtonPushedFcn = createCallbackFcn(app, @VP_ReturnBtnPushed, true);

            %  SCAN & LOAD PANEL
            app.ScanPanel = mkPanel(app.UIFigure, [0 0 W H], 'Optical Automation Module Interface');

            app.SC_Title = uilabel(app.ScanPanel); app.SC_Title.Text = 'Protocol Verification: Optical Barcode Intercept & Compartment Dispatch';
            app.SC_Title.FontSize = 12; app.SC_Title.FontColor = [0.12 0.45 0.74]; app.SC_Title.Position = [15 510 700 22];

            app.SC_Axes = uiaxes(app.ScanPanel); app.SC_Axes.Position = [15 200 470 295];
            app.SC_Axes.XTick = []; app.SC_Axes.YTick = []; title(app.SC_Axes, 'Optical Sensor Live Capture Stream');

            app.SC_CamLabel = uilabel(app.ScanPanel); app.SC_CamLabel.Text = 'Status: Optical Hardware Idle';
            app.SC_CamLabel.FontSize = 11; app.SC_CamLabel.Position = [15 178 300 18];

            app.SC_StartBtn = uibutton(app.ScanPanel,'push'); app.SC_StartBtn.Text = 'START SENSOR';
            app.SC_StartBtn.Position = [15 145 140 30]; app.SC_StartBtn.BackgroundColor = [0.12 0.45 0.74];
            app.SC_StartBtn.FontColor = [1 1 1]; app.SC_StartBtn.FontWeight = 'bold';
            app.SC_StartBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_StartBtnPushed, true);

            app.SC_StopBtn = uibutton(app.ScanPanel,'push'); app.SC_StopBtn.Text = 'STOP SENSOR';
            app.SC_StopBtn.Position = [165 145 140 30]; app.SC_StopBtn.BackgroundColor = [1.00 1.00 1.00];
            app.SC_StopBtn.FontColor = [0.70 0.20 0.20]; app.SC_StopBtn.FontWeight = 'bold';
            app.SC_StopBtn.Enable = 'off'; app.SC_StopBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_StopBtnPushed, true);

            serialBox = uipanel(app.ScanPanel); serialBox.Title = 'Hardware Pipeline Link (ESP32 Controller)';
            serialBox.Position = [500 330 260 160]; serialBox.BackgroundColor = [0.97 0.98 0.99];

            app.SC_ComField = uieditfield(serialBox,'text'); app.SC_ComField.Position = [105 108 140 24];
            app.SC_ComField.Placeholder = 'COM3'; app.SC_ComField.BackgroundColor = [1.00 1.00 1.00];

            app.SC_ConnectBtn = uibutton(serialBox,'push'); app.SC_ConnectBtn.Text = 'LINK INTERFACE';
            app.SC_ConnectBtn.Position = [10 70 115 28]; app.SC_ConnectBtn.FontWeight = 'bold';
            app.SC_ConnectBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_ConnectBtnPushed, true);

            app.SC_DisconnectBtn = uibutton(serialBox,'push'); app.SC_DisconnectBtn.Text = 'DROP LINK';
            app.SC_DisconnectBtn.Position = [135 70 115 28]; app.SC_DisconnectBtn.FontWeight = 'bold';
            app.SC_DisconnectBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_DisconnectBtnPushed, true);

            infoBox = uipanel(app.ScanPanel); infoBox.Title = 'Decoded Stream Telemetry';
            infoBox.Position = [500 150 260 170]; infoBox.BackgroundColor = [0.97 0.98 0.99];

            app.SC_BarcodeLabel = uilabel(infoBox); app.SC_BarcodeLabel.Text = 'Barcode Matrix: Null';
            app.SC_BarcodeLabel.WordWrap = 'on'; app.SC_BarcodeLabel.Position = [8 110 240 28];

            app.SC_CommandLabel = uilabel(infoBox); app.SC_CommandLabel.Text = 'Parsed Core Directive: Null';
            app.SC_CommandLabel.WordWrap = 'on'; app.SC_CommandLabel.Position = [8 75 240 28];

            app.SC_SendLabel = uilabel(infoBox); app.SC_SendLabel.Text = 'Serial Channel Activity Log: Null';
            app.SC_SendLabel.WordWrap = 'on'; app.SC_SendLabel.FontSize = 10; app.SC_SendLabel.Position = [8 10 240 56];

            % Extra Mile: UI Error Recovery Button Trigger
            app.SC_RecoveryBtn = uibutton(app.ScanPanel, 'push');
            app.SC_RecoveryBtn.Text = 'FORCE HARDWARE PIPELINE RECOVERY';
            app.SC_RecoveryBtn.Position = [500 100 260 30];
            app.SC_RecoveryBtn.BackgroundColor = [0.98 0.92 0.92];
            app.SC_RecoveryBtn.FontColor = [0.70 0.20 0.20]; app.SC_RecoveryBtn.FontWeight = 'bold';
            app.SC_RecoveryBtn.ButtonPushedFcn = @(~,~) executeErrorRecovery(app);

            app.SC_ReturnBtn = uibutton(app.ScanPanel,'push'); app.SC_ReturnBtn.Text = 'RETURN';
            app.SC_ReturnBtn.Position = [W-120 15 100 28]; app.SC_ReturnBtn.BackgroundColor = [1.00 1.00 1.00];
            app.SC_ReturnBtn.ButtonPushedFcn = createCallbackFcn(app, @SC_ReturnBtnPushed, true);

            app.UIFigure.Visible = 'on';
        end

        function cbs = buildHourCheckboxes(~, parentTab, hours)
            cbs = {}; colBreak = 12;
            for k = 1:numel(hours)
                h = hours(k); col = (k > colBreak); row = mod(k-1, colBreak);
                x = 20 + col * 160; y = 340 - row * 24;
                cb = uicheckbox(parentTab); cb.Text = sprintf('%02d:00 Hours', h);
                cb.Position = [x y 120 20]; cbs{end+1} = cb; %#ok<AGROW>
            end
        end
    end

    %  APP LIFECYCLE 
    methods (Access = public)
        function app = MedDispenserApp
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0, clear app; end
        end

        function delete(app)
            stopCamera(app);
            if ~isempty(app.SerialObj), delete(app.SerialObj); end
            delete(app.UIFigure)
        end
    end
end

%  MODULE-LEVEL HELPERS 
function txt = formatSchedule(cellArr)
    if isempty(cellArr), txt = 'No periods programmed'; else, txt = strjoin(cellArr, '  |  '); end
end