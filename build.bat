@echo off
setlocal

rem Inject the build date (BuildyyMMdd) into APP_VERSION via --dart-define.
rem It is read by String.fromEnvironment in translations.dart and shown in Settings > About.
rem Usage: build.bat [extra flutter build windows args, e.g. --debug]

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyMMdd"') do set BUILD_DATE=%%i

echo Building with APP_VERSION=Build%BUILD_DATE% ...
flutter build windows --release --dart-define=APP_VERSION=Build%BUILD_DATE% %*

endlocal
