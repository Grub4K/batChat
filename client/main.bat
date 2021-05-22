@echo off
:: Change these to the current host
set "HOST_URL="
set "deltaRecv=200"
set "deltaTokRenew=30000"

if "%~1" == "startMain" goto :mainSetup
if "%~1" == "startController" goto :controller
title BatChat v1.0
mode 108,40
goto :getSession



:main
for /L %%. in ( infinite ) do (
    if "!prog_state!"=="login" (
        %= PROMPT FOR USERNAME AND PASSWORD =%
        %@emitLoginPrompt%
        <NUL set /p "=%ESC%[19;44H"
        call :getString username 20
        if not defined username (
            %@sendCmd% quit
            %@useMainBuffer%
            exit
        )
        <NUL set /p "=%ESC%[21;44H"
        call :getString password 20 masked
        if defined password call :tryLogin username password
    ) else if "!prog_state!"=="chat" (
        for /f "tokens=1-4 delims=:.," %%a in ("!time: =0!") do (
            set /a "t0=(((1%%a*60)+1%%b)*60+1%%c)*100+1%%d-36610100, tRecvDiff=t0-t1, tRecvDiff+=((~(tRecvDiff&(1<<31))>>31)+1)*8640000, tTokDiff=t0-t2, tTokDiff+=((~(tTokDiff&(1<<31))>>31)+1)*8640000"
        )
        %= Set flags for special timed events =%
        if !tRecvDiff! geq !deltaRecv! set /a "t1=t0, shouldReceive=1"
        if !tTokDiff! geq !deltaTokRenew! set /a "t2=t0, shouldRenewToken=1"

        %= PERFORM QUEUED EVENTS =%
        if defined shouldReceive call :tryRecv
        if defined shouldRenewToken call :tryRenewToken

        (%@getKey% !freeInput! )
        if defined key (
            if !key! equ {Enter} (
                %@clrInputPrompt%
                set "message=!msgPrompt!"
                set "msgPrompt="
                set "msgPromptLen=0"
                if "!message:~0,1!"=="/" (
                    for /F "tokens=1 delims= " %%a in ("!message:~1!") do (
                        if "%%~a"=="quit" (
                            call :tryLogout
                            %@sendCmd% quit
                            %@useMainBuffer%
                            exit
                        ) else if "%%~a"=="logout" (
                            call :tryLogout
                        )
                    )
                ) else (
                    if defined message call :trySend message
                )
            ) else if !key! neq !BS! (
                if not defined msgPrompt %@clrInputPrompt%
                if !msgPromptLen! leq 100 (
                    set /a "msgPromptLen+=1"
                    <nul set /p "=.!BS! !BS!!key!"
                    set "msgPrompt=!msgPrompt!!key!"
                )
            ) else if defined msgPrompt (
                set /a msgPromptLen-=1
                <nul set /p "=!BS! !BS!"
                set "msgPrompt=!msgPrompt:~0,-1!"
            )
            if not defined msgPrompt if "!prog_state!"=="chat" %@emitMsgPrompt%
        )
    )
)
exit /B

:tryLogout
call :doProtocolRequest /logout
if !errorlevel! equ 0 (
    %@emitStatus% "Successfully logged out..."
) else (
    %@emitStatus% "Failed to properly log out..."
)
(
    %@clrMessageDisplay%
    %@clrStatus%
)
set "session.token="
set "prog_state=login"
exit /B

:trySend  <messageVar>
:: Sanitize message
set "request.message=!%~1!"
set "request.message=!request.message:"=""!"
set "request.message=!request.message:%%=%%25!"
set "request.message=!request.message:&=%%26!"
set "request.message=!request.message:+=%%2B!"
set "request.message=!request.message:\=%%5C!"

call :doProtocolRequestEmit /send || (
    set "msgToEmit=%ESC%[7m%ESC%[31mFailed to deliver Message...%ESC%[0m"
    %@emitMessage% SYSTEM msgToEmit
)
set "request.message="
exit /B

:tryRecv
call :doProtocolRequestEmit /recv result || exit /B
if defined result (
    if "!result:~0,3!"=="END" (
        set "shouldReceive="
        exit /B
    )
    for /F "tokens=1 delims=:" %%a in ("!result:~4!") do set "user=%%~a"
    call :emitMsgAdvanced  !user! result
)
exit /B

:: Mechanism for token renewing thats not yet part of batChat protocol
:tryRenewToken
exit /B

:emitMsgAdvanced  <username> <msgToEmit>
set "colorSet="
set "msgToEmit=  "
set "msg=!%~2:*:=!"
:: Expand escape codes
for /L %%a in ( 1 1 50 ) do (
    if defined msg if "!msg!" neq "\" (
        set "afterMsg=!msg:*\=!"
        if "!afterMsg!" neq "!msg!" (
            %@strLen% afterMsg tempLen
            for %%b in ("!tempLen!") do set "preMsg=!msg:~0,-%%~b!"
            set "preMsg=!preMsg:~0,-1!"
            if "!afterMsg:~0,1!"=="\" (
                set "preMsg=!preMsg!\"
            ) else if "!afterMsg:~0,1!"=="I" (
                set "preMsg=!preMsg!^!"
            ) else if "!afterMsg:~0,1!"=="n" (
                set "msgToEmit=!msgToEmit!!preMsg!"
                if defined colorSet set "msgToEmit=!msgToEmit!%ESC%[0m"
                (%@emitMessage% %~1 msgToEmit)
                set "colorSet="
                set "msgToEmit=  "
                set "preMsg="
            ) else if "!afterMsg:~0,1!"=="c" (
                if !tempLen! geq 6 (
                    set "isValid=1"
                    for /F "delims=0123456789ABCDEFabcdef" %%a in ("!afterMsg:~0,6!") do set "isValid="
                    if defined isValid (
                        set "colorSet=1"
                        set /a "r=0x!afterMsg:~1,2!, g=0x!afterMsg:~3,2!, b=0x!afterMsg:~5,2!"
                        set "preMsg=!preMsg!%esc%[38;2;!r!;!g!;!b!m"
                        set "afterMsg=!afterMsg:~6!"
                    )
                )
            )
            set "msg=!afterMsg:~1!"
            set "msgToEmit=!msgToEmit!!preMsg!"
        )
    )
)
set "msgToEmit=!msgToEmit!!msg!"
if defined colorSet set "msgToEmit=!msgToEmit!%ESC%[0m"
(%@emitMessage% %~1 msgToEmit)
exit /B

:tryLogin  <usernameVar> <passwordVar>
set "request.username=!%~1!"
set "request.password=!%~2!"
call :doProtocolRequest /login request.token && (
    set "request.username="
    set "request.password="
    set "prog_state=chat"
    set "msgPrompt="
    set "msgPromptLen=0"
    set "lastSender="
    set "shouldReceive="
    set "shouldRenewToken="

    %@clrMessageDisplay%
    %@setCursorAtInLine%
    %@emitStatus% "Logged in as !username!"
    %@emitMsgPrompt%
    call :tryRecv
    %@sendCmd% go

    for /f "tokens=1-4 delims=:.," %%a in ("!time: =0!") do set /a "t1=(((1%%a*60)+1%%b)*60+1%%c)*100+1%%d-36610100, t2=t1"
    exit /B
)
(%@emitStatus% "Login failed, please try again...")
exit /B

:checkConnection
set "success="
(%@emitStatus% "Trying to connect to endpoint...")
for /F "delims=" %%a in ('curl -s --connect-timeout 5 %HOST_URL%/') do (
    if "%%~a" equ "BatChat v1.0" set "success=1"
)
if not defined success (
    (%@emitStatus% "Did not recieve correct response...")
    %@sendCmd% quit
    exit
)
exit /B

:doProtocolRequestEmit  <route> <dataDict>
call :doProtocolRequest "%~1" "%~2" && (
    %@setStatusOnline%
    exit /B 0
) || (
    %@setStatusOffline%
    exit /B 1
)
exit /B

:doProtocolRequest  <route> [resultVar]
set "data="
for /F "tokens=2 delims==." %%a in ('set request.') do (
    set "data=!data! -d "%%a=!request.%%a!""
)
set "first=1"
set "second="
for /F "delims=" %%a in ('curl -s --max-time 2 -X POST !data! %HOST_URL%%~1') do (
    if defined second (
        set "%~2=%%a"
        if defined %~2 exit /B 0
        exit /B 1
    )
    if defined first (
        set "first="
        if "%%a"=="fail" exit /B 1
        if "%%a"=="success" (
            if "%~2" neq "" (
                set "second=1"
            ) else exit /B 0
        ) else exit /B 2
    )
)
exit /B 3

:getSession
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "tempFileBase=%%a"
set "tempFileBase=%tempFileBase:.=%"
set "tempFileBase=%tempFileBase:~0,-7%"
set "tempFileBase=%~dp0sessions\%tempFileBase%\"
set "keyFile=%tempFileBase%key.txt"
set "cmdFile=%tempFileBase%cmd.txt"
set "gameLock=%tempFileBase%lock.txt"
set "signal=%tempFileBase%signal.txt"
set "keyStream=9"
set "cmdStream=8"
set "lockStream=7"
if not exist "%tempFileBase%" md "%tempFileBase%"
call :launch %lockStream%>"%gameLock%" || goto :getSession
rd /s /q "%tempFileBase%"
exit /b

:: launch the main program and the controller
:launch
copy nul "%keyFile%" >nul
copy nul "%cmdFile%" >nul
start "" /b cmd /c ^""%~f0" startController %keyStream%^>^>"%keyFile%" %cmdStream%^<"%cmdFile%" 2^>nul ^>nul^"
cmd /c ^""%~f0" startMain  %keyStream%^<"%keyFile%" %cmdStream%^>^>"%cmdFile%" ^<nul 2^>NUL ^"
set "closeCount=0"
:close
if %closeCount% equ 0 (
    set "closeCount=1"
) else if %closeCount% equ 1 (
    <NUL set /P "=Press any button to properly terminate..."
    set "closeCount=2"
)
2>nul (>>"%keyFile%" call ) || goto :close
exit /b 0

:mainSetup
setlocal disableDelayedExpansion
:: define LF as a Line Feed (newline) character
set ^"LF=^
%= This line is required =%
^" do not remove

:: define CR as a Carriage Return character
for /f %%A in ('copy /Z "%~dpf0" nul') do set "CR=%%A"

:: define BS as a BackSpace character
for /f %%A in ('"prompt $H&for %%B in (1) do rem"') do set "BS=%%A"

for /f "delims=" %%E in ('forfiles /p "%~dp0." /m "%~nx0" /c "cmd /c echo(0x1B"') do set "ESC=%%E"

:: define a newline with line continuation
set ^"\n=^^^%LF%%LF%^%LF%%LF%^^"

:: getKey  [validKey [validKey [...]]]
::: Check for keypress from the controller. Only accept a ValidKey.
::: Token delimiters and poison characters must be quoted.
::: Accept any key if no ValidKey specified.
::: Return result in Key variable. Key is undefined if no valid keypress.
set @getKey=for %%# in (1 2) do if %%#==2 (%\n%
    set "key="%\n%
    set "inKey="%\n%
    set "keyTest="%\n%
    ^<^&%keyStream% set /p "inKey="%\n%
    if defined inKey (%\n%
        set "inKey=!inKey:~0,-1!"%\n%
        for %%C in (!args!) do (%\n%
            set /a "keyTest=1" %\n%
            if /i !inKey! equ %%~C set "key=!inKey!"%\n%
        )%\n%
        if not defined keyTest set key=!inKey!%\n%
    )%\n%
) else set args=

::@strLen  <strVar> <RtnVar>
set @strLen=for %%# in (1 2) do if %%#==2 (%\n%
    for /f "tokens=1,2 delims=, " %%1 in ("!argv!") do ( endlocal%\n%
        set "s=A!%%~1!"%\n%
        set "len=0"%\n%
        for %%P in (4096 2048 1024 512 256 128 64 32 16 8 4 2 1) do (%\n%
            if "!s:~%%P,1!" neq "" (%\n%
                set /a "len+=%%P"%\n%
                set "s=!s:~%%P!"%\n%
            )%\n%
        )%\n%
        for %%V in (!len!) do endlocal^&set "%%~2=%%V"%\n%
    )%\n%
) else setlocal enableDelayedExpansion^&setlocal^&set argv=,

:: @sendCmd  <command>
:::  sends a command to the controller
set "@sendCmd=>&%cmdStream% echo"

:: TODO: dynamically assign this using bounds

set "_preLine=%ESC%[1S%ESC%[35;2Hº "
set "_aftLine=%ESC%[107Gº"

set @setStatusOnline=^<NUL set /p "=%ESC%7%ESC%[3;99H%ESC%[92mONLINE %ESC%[0m%ESC%8"

set @setStatusOffline=^<NUL set /p "=%ESC%7%ESC%[3;99H%ESC%[31mOFFLINE%ESC%[0m%ESC%8"

set @clrStatus=^<NUL set /p "=%ESC%7%ESC%[3;99H%ESC%[31m       %ESC%[0m%ESC%8"

set @emitMsgPrompt=^<NUL set /p "=%ESC%[5G%ESC%[38;2;100;100;100mEnter Message%ESC%[0m%ESC%[5G"

set @clrInputPrompt=^<NUL set /p "=%ESC%[2K%ESC%[106G³º%ESC%[2Gº³ "

set @useAltBuffer=^<NUL set /p "=%ESC%[?1049h"
set @useMainBuffer=^<NUL set /p "=%ESC%[?1049l"

:: @emitMessage  <name> <messageVar>
:::  sends a new Message to the screen, scrolling the buffer when needed
:::  Automatically prepends sender name if not last sender
set @emitMessage=for %%# in (1 2) do if %%#==2 (%\n%
    for /f "tokens=1,2 delims=, " %%1 in ("!argv!") do (%\n%
        set "emit="%\n%
        if "!lastSender!" neq "%%1" if "%%1" neq "SYSTEM" (%\n%
            set "lastSender=%%1"%\n%
            set "emit=%ESC%[4m%ESC%[38;2;255;170;0m%%1%ESC%[0m%_aftLine%%_preLine%"%\n%
        )%\n%
        ^<NUL set /p ".=%ESC%7%_preLine%!emit!!%%2!%_aftLine%%ESC%8"%\n%
    )%\n%
) else set argv=,

set @emitLoginPrompt=for %%# in (%\n%
    "17;41HÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»"%\n%
    "18;41HºÚÄ Username ÄÄÄÄÄÄÄÄÄÄÄ¿º"%\n%
    "19;41Hº³                      ³º"%\n%
    "20;41HºÃÄ Password ÄÄÄÄÄÄÄÄÄÄÄ´º"%\n%
    "21;41Hº³                      ³º"%\n%
    "22;41HºÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙº"%\n%
    "23;41HÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼"%\n%
) do echo:%ESC%[%%~#

set "emptyLine=                                                                                            "

set @emitStatus=for %%# in (1 2) do if %%#==2 (for %%1 in (!argv!) do (%\n%
    ^<NUL set /p "=%ESC%7%ESC%[3;4H%emptyLine%%ESC%[3;4H%%~1%ESC%8"%\n%
)) else set argv=

set "exclam=!"
set "quote=""
set "caret=^"
set "percent=%%"

set @setCursorAtInLine=^<NUL set /p "=%ESC%[37;5H"

setlocal EnableDelayedExpansion
set @clrMessageDisplay=^<NUL set /p "=%ESC%7
for /L %%. in ( 1 1 31 ) do set "@clrMessageDisplay=!@clrMessageDisplay!%ESC%[1S%ESC%[35;2Hº%ESC%[107Gº"
set "@clrMessageDisplay=!@clrMessageDisplay!%ESC%8""

set "upper=A B C D E F G H I J K L M N O P Q R S T U V W X Y Z"
set "num=0 1 2 3 4 5 6 7 8 9"
set "alNum=!upper! !num!"

:: `*` and `?` do not work
set "freeInput=!alNum! {Enter} !BS! ø "=" { } !percent! !caret! $ õ # \ < > | + ` ~ ' : @ ";" [ ] "," . / _ - ( ) !quote!"

set "usernameInput=!alNum! _ - {Enter} !BS!"

set "prog_state=login"


%@useAltBuffer%


<NUL set /p "=%ESC%[5;35r"
echo:
echo  ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍËÍÍÍÍÍÍÍÍÍ»
echo  º                                                                                              º         º
echo  ÌÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÊÍÍÍÍÍÍÍÍÍ¹
echo %ESC%[36;2HºÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿º
echo  º³                                                                                                      ³º
echo  ºÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙº
echo  ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼

(
    %@clrMessageDisplay%
    call :checkConnection
    %@emitStatus% "Please enter your login data..."
)

goto :main

:getString  <retVar> <maxlen> <masked>
:: prompt for a string with max lengh of maxlen.
:: Valid keys are alpha-numeric, space, underscore, and dash
:: String is terminated by Enter
:: Backspace works to delete previous character
:: Result is returned in retVar
:: if masked is set, mask input and higher selection of characters
if "%~3" == "" (
    set "mask=^!key^!"
    set "valid=!usernameInput!"
) else (
    set "mask=*"
    set "valid=!freeInput!"
)
set /a "maxLen=%2"
set "%1="
%@sendCmd% prompt
call :purge
:getStringLoop
(%@getKey% !valid!)
if defined key (
    if !key! equ {Enter} exit /b
    if !key! neq !BS! (
        if !maxLen! gtr 0 (
            set /a maxLen-=1
            <nul set /p ".=.!BS!%mask%"
            set "%1=!%1!!key!"
        )
    ) else if defined %1 (
          set /a maxLen+=1
          <nul set /p ".=!BS! !BS!"
          set "%1=!%1:~0,-1!"
    )
)
if defined inKey %@sendCmd% one
goto :getStringLoop

:pause
%@sendCmd% prompt
call :purge
exit /B

:purge
set "inKey="
for /l %%N in ( 1 1 1000 ) do (
    set /p "inKey= "
    if "!inKey!" equ "{purged}." exit /B
)<&%keyStream%
goto :purge

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:controller
:: Detects keypresses and sends the information to the game via a key file.
:: This routine incorrectly reports `!` as something else. Both <CR> and the
:: Enter key are reported as {Enter}. An extra character is appended to the
:: output to preserve any control chars when read by SET /P.
setlocal enableDelayedExpansion
for /f %%a in ('copy /Z "%~dpf0" nul') do set "CR=%%a"
set "cmd=one"
set "inCmd="
set "key="
for /l %%. in () do (
    if "!cmd!" neq "hold" (
        for /f "delims=" %%A in ('xcopy /w "%~f0" "%~f0" 2^>nul') do (
            if not defined key set "key=%%A"
        )
        set "key=!key:~-1!"
        if !key! equ !CR! set "key={Enter}"
    )
    <&%cmdStream% set /p "inCmd="
    if defined inCmd (
        if !inCmd! equ quit exit
        set "cmd=!inCmd!"
        set "inCmd="
    )
    if defined key (
        if "!cmd!" equ "prompt" (echo {purged}.)
        (echo(!key!.)
        if "!cmd!" neq "go" set "cmd=hold"
        set "key="
    )>&%keyStream%
)
