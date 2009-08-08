{$I Defines.inc}

unit PanelTabsCtrl;

{******************************************************************************}
{* (c) 2009 Max Rusov                                                         *}
{*                                                                            *}
{* PanelTabs Far plugin                                                       *}
{******************************************************************************}

interface

  uses
    Windows,
    MixTypes,
    MixUtils,
    MixStrings,
    MixWinUtils,

   {$ifdef bUnicodeFar}
    PluginW,
   {$else}
    Plugin,
   {$endif bUnicodeFar}

    FarCtrl,
    FarConMan,
    FarMatch;


  type
    TMessages = (
      strLang,
      strTitle,
      strError,

      strTabs,

      strMAddTab,
      strMEditTabs,
      strMSelectTab,
      strMOptions,

      strOptions,
      strMShowTabs,
      strMShowNumbers,
      strMShowButton,
      strMSeparateTabs,

      strEditTab,
      strAddTab,
      strCaption,
      strFolder,
      strOk,
      strCancel,
      strDelete,

      strEmptyCaption,
      strUnknownCommand
    );


  const
    cFarTabGUID      = $A91B3F07;
    cFarTabPrefix    = 'tab';

    cTabFileExt      = 'tab';

    cPlugRegFolder   = 'PanelTabs';
    cTabsRegFolder   = 'Tabs';
    cTabRegFolder    = 'Tab';
    cLeftRegFolder   = 'Left';
    cRightRegFolder  = 'Right';
    cCommonRegFolder = 'Common';
    cCaptionRegKey   = 'Caption';
    cFolderRegKey    = 'Folder';

  var
    optShowTabs        :Boolean = True;
    optShowNumbers     :Boolean = True;
    optShowButton      :Boolean = True;
    optSeparateTabs    :Boolean = True;

    optBkColor         :Integer = 0;
    optActiveTabColor  :Integer = 0;
    optPassiveTabColor :Integer = 0;
    optNumberColor     :Integer = 0;
    optButtonColor     :Integer = 0;

//  optHiddenColor     :Integer = 0;
//  optFoundColor      :Integer = $0A;
//  optSelectedColor   :Integer = $20;

   {$ifdef bUnicode}
   {$else}
    TabKey1            :Word    = 0; {VK_F24 - $87}
    TabShift1          :Word    = 0; {LEFT_ALT_PRESSED or SHIFT_PRESSED}
   {$endif bUnicode}



  var
    FRegRoot  :TString;

  var
    hFarWindow  :THandle = THandle(-1);
    hConEmuWnd  :THandle = THandle(-1);


  function GetMsg(AMess :TMessages) :PFarChar;
  function GetMsgStr(AMess :TMessages) :TString;
  procedure AppErrorId(AMess :TMessages);
  procedure AppErrorIdFmt(AMess :TMessages; const Args: array of const);
  procedure HandleError(AError :Exception);

  function hConsoleWnd :THandle;
  function GetConsoleTitleStr :TString;
  function GetConsoleMousePos :TPoint;
    { ��������� ������� ���� � ���������� ����������� }
  function ReadScreenChar(X, Y :Integer) :TChar;
    { �������� ������ �� ������� X, Y }

  function VKeyToIndex(AKey :Integer) :Integer;
  function IndexToChar(AIndex :Integer) :TChar;

  function CurrentPanelIsRight :Boolean;
  function GetPanelDir(Active :Boolean) :TString;
  procedure JumpToPath(const APath :TString; Active :Boolean);

  procedure ReadSetup;
  procedure WriteSetup;

{******************************************************************************}
{******************************} implementation {******************************}
{******************************************************************************}

  uses
    MixDebug;


  function GetMsg(AMess :TMessages) :PFarChar;
  begin
    Result := FarCtrl.GetMsg(Integer(AMess));
  end;

  function GetMsgStr(AMess :TMessages) :TString;
  begin
    Result := FarCtrl.GetMsgStr(Integer(AMess));
  end;

  procedure AppErrorId(AMess :TMessages);
  begin
    FarCtrl.AppErrorID(Integer(AMess));
  end;

  procedure AppErrorIdFmt(AMess :TMessages; const Args: array of const);
  begin
    FarCtrl.AppErrorIdFmt(Integer(AMess), Args);
  end;


  procedure HandleError(AError :Exception);
  begin
    ShowMessage('PanelTabs', AError.Message, FMSG_WARNING or FMSG_MB_OK);
  end;


  function GetConsoleTitleStr :TString;
  var
    vBuf :Array[0..1024] of TChar;
  begin
    FillChar(vBuf, SizeOf(vBuf), $00);
    GetConsoleTitle(@vBuf[0], High(vBuf));
    Result := vBuf;

    if ConManDetected then
      ConManClearTitle(Result);

//  TraceF('GetConsoleTitleStr: %s', [Result]);
  end;


  function hConsoleWnd :THandle;
  var
    hWnd :THandle;
  begin
    Result := hFarWindow;
    if not IsWindowVisible(hFarWindow) then begin
      { �������� ��-��� ConEmu?... }
      hWnd := GetAncestor(hFarWindow, GA_PARENT);

      if (hWnd = 0) or (hWnd = GetDesktopWindow) then begin
        { ����� ������ ConEmu �� ������ SetParent... }
        if hConEmuWnd = THandle(-1) then
          hConEmuWnd := CheckConEmuWnd;
        hWnd := hConEmuWnd;
      end;

      if hWnd <> 0 then
        Result := hWnd;
    end;
  end;


  function MulDivTrunc(ANum, AMul, ADiv :Integer) :Integer;
  begin
    if ADiv = 0 then
      Result := 0
    else
      Result := ANum * AMul div ADiv;
  end;


  function GetConsoleMousePos :TPoint;
  var
    vWnd  :THandle;
    vPos  :TPoint;
    vRect :TRect;
    vInfo :TConsoleScreenBufferInfo;
  begin
    GetCursorPos(vPos);

    vWnd := hConsoleWnd;
    ScreenToClient(vWnd, vPos);
    GetClientRect(vWnd, vRect);
    GetConsoleScreenBufferInfo(hStdOut, vInfo);

    with vInfo.srWindow do begin
//    TraceF('%d, %d - %d, %d', [Left, Top, Right, Bottom]);
      Result.Y := Top + MulDivTrunc(vPos.Y, Bottom - Top + 1, vRect.Bottom - vRect.Top);
      Result.X := Left + MulDivTrunc(vPos.X, Right - Left + 1, vRect.Right - vRect.Left);
    end;
  end;


  function ReadScreenChar(X, Y :Integer) :TChar;
  var
    vInfo :TConsoleScreenBufferInfo;
    vBuf :array[0..1, 0..1] of TCharInfo;
    vSize, vCoord :TCoord;
    vReadRect :TSmallRect;
  begin
    Result := #0;
    GetConsoleScreenBufferInfo(hStdOut, vInfo);
    if (X < vInfo.dwSize.X) and (Y < vInfo.dwSize.Y) then begin

      vSize.X := 1; vSize.Y := 1; vCoord.X := 0; vCoord.Y := 0;
      vReadRect := SBounds(X, Y, 1, 1);
      FillChar(vBuf, SizeOf(vBuf), 0);

      if ReadConsoleOutput(hStdOut, @vBuf, vSize, vCoord, vReadRect) then
       {$ifdef bUnicode}
        Result := vBuf[0, 0].UnicodeChar;
       {$else}
        Result := vBuf[0, 0].AsciiChar;
       {$endif bUnicode}

    end;
  end;


  function CurrentPanelIsRight :Boolean;
  var
    vInfo  :TPanelInfo;
  begin
    FillChar(vInfo, SizeOf(vInfo), 0);
   {$ifdef bUnicodefar}
    FARAPI.Control(THandle(PANEL_ACTIVE), FCTL_GetPanelInfo, 0, @vInfo);
   {$else}
    FARAPI.Control(INVALID_HANDLE_VALUE, FCTL_GetPanelShortInfo, @vInfo);
   {$endif bUnicodefar}
    Result := (PFLAGS_PANELLEFT and vInfo.Flags = 0);
  end;


  function GetPanelDir(Active :Boolean) :TString;
 {$ifdef bUnicodeFar}
 {$else}
  var
    vInfo :TPanelInfo;
 {$endif bUnicodeFar}
  begin
   {$ifdef bUnicodeFar}
    Result := FarPanelGetCurrentDirectory(THandle(IntIf(Active, PANEL_ACTIVE, PANEL_PASSIVE)));
   {$else}
    FillChar(vInfo, SizeOf(vInfo), 0);
    FARAPI.Control(INVALID_HANDLE_VALUE, IntIf(Active, FCTL_GetPanelInfo, FCTL_GetAnotherPanelInfo), @vInfo);
    Result := StrOemToAnsi(vInfo.CurDir);
   {$endif bUnicodeFar}
  end;


  procedure JumpToPath(const APath :TString; Active :Boolean);
  var
    vStr :TFarStr;
    vMacro :TActlKeyMacro;
  begin
   {$ifndef bUnicode}
    SetFileApisToOEM;
    try
   {$endif bUnicode}

    if IsFullFilePath(APath) then begin
     {$ifdef bUnicodeFar}
      FARAPI.Control(THandle(IntIf(Active, PANEL_ACTIVE, PANEL_PASSIVE)), FCTL_SETPANELDIR, 0, PFarChar(APath));
      FARAPI.Control(THandle(IntIf(Active, PANEL_ACTIVE, PANEL_PASSIVE)), FCTL_REDRAWPANEL, 0, nil);
     {$else}
      vStr := StrAnsiToOem(APath);
      FARAPI.Control(INVALID_HANDLE_VALUE, IntIf(Active, FCTL_SETPANELDIR, FCTL_SETANOTHERPANELDIR), PFarChar(vStr));
      FARAPI.Control(INVALID_HANDLE_VALUE, IntIf(Active, FCTL_REDRAWPANEL, FCTL_REDRAWANOTHERPANEL), nil);
     {$endif bUnicodeFar}
    end else
    if APath <> '' then begin
     {$ifdef bUnicodeFar}
      FARAPI.Control(INVALID_HANDLE_VALUE, FCTL_SETCMDLINE, 0, PFarChar(APath));
     {$else}
      vStr := StrAnsiToOem(APath);
      FARAPI.Control(INVALID_HANDLE_VALUE, FCTL_SETCMDLINE, PFarChar(vStr));
     {$endif bUnicodeFar}

      if Active then
        vStr := 'Enter'
      else
        vStr := 'Tab Enter Tab';
      vMacro.Command := MCMD_POSTMACROSTRING;
      vMacro.Param.PlainText.SequenceText := PFarChar(vStr);
      vMacro.Param.PlainText.Flags := KSFLAGS_DISABLEOUTPUT or KSFLAGS_NOSENDKEYSTOPLUGINS;
      FARAPI.AdvControl(hModule, ACTL_KEYMACRO, @vMacro);
    end else
      Beep;

   {$ifndef bUnicode}
    finally
      SetFileApisToAnsi;
    end;
   {$endif bUnicode}
  end;


  function VKeyToIndex(AKey :Integer) :Integer;
  begin
    Result := -1;
    case AKey of
      Byte('1')..Byte('9'):
        Result := AKey - Byte('1');
      Byte('a')..Byte('z'):
        Result := AKey - Byte('a') + 9;
      Byte('A')..Byte('Z'):
        Result := AKey - Byte('A') + 9;
    end;
  end;


  function IndexToChar(AIndex :Integer) :TChar;
  begin
    if AIndex < 9 then
      Result := TChar(Byte('1') + AIndex)
    else
      Result := TChar(Byte('A') + AIndex - 9);
  end;


 {-----------------------------------------------------------------------------}

  procedure ReadSetup;
  var
    vKey :HKEY;
  begin
    if not RegOpenRead(HKCU, FRegRoot + '\' + cPlugRegFolder, vKey) then
      Exit;
    try
     {$ifdef bUnicode}
     {$else}
      TabKey1 := RegQueryInt(vKey, 'CallKey', TabKey1);
      TabShift1 := RegQueryInt(vKey, 'CallShift', TabShift1);
     {$endif bUnicode}

      optBkColor := RegQueryInt(vKey, 'TabBkColor', optBkColor);
      optActiveTabColor := RegQueryInt(vKey, 'ActiveTabColor', optActiveTabColor);
      optPassiveTabColor := RegQueryInt(vKey, 'PassiveTabColor', optPassiveTabColor);
      optNumberColor := RegQueryInt(vKey, 'NumberColor', optNumberColor);
      optButtonColor := RegQueryInt(vKey, 'ButtonColor', optButtonColor);

//    optHiddenColor := RegQueryInt(vKey, 'HiddenColor', optHiddenColor);
//    optFoundColor := RegQueryInt(vKey, 'FoundColor', optFoundColor);
//    optSelectedColor := RegQueryInt(vKey, 'SelectedColor', optSelectedColor);

      optShowTabs := RegQueryLog(vKey, 'ShowTabs', optShowTabs);
      optShowNumbers := RegQueryLog(vKey, 'ShowNumbers', optShowNumbers);
//    optShowButton := RegQueryLog(vKey, 'ShowButton', optShowButton);
      optSeparateTabs := RegQueryLog(vKey, 'SeparateTabs', optSeparateTabs);

    finally
      RegCloseKey(vKey);
    end;
  end;


  procedure WriteSetup;
  var
    vKey :HKEY;
  begin
    RegOpenWrite(HKCU, FRegRoot + '\' + cPlugRegFolder, vKey);
    try

      RegWriteLog(vKey, 'ShowTabs', optShowTabs);
      RegWriteLog(vKey, 'ShowNumbers', optShowNumbers);
//    RegWriteLog(vKey, 'ShowButton', optShowButton);
      RegWriteLog(vKey, 'SeparateTabs', optSeparateTabs);

    finally
      RegCloseKey(vKey);
    end;
  end;


end.

