@echo off
echo Rebuilding LightScope Windows Installer with fixes...
"C:\Program Files (x86)\NSIS\makensis.exe" /DOUTFILE="C:\Users\Eric\Desktop\thelightscope\windows-output\LightScope-0.0.102-Setup-Fixed.exe" "lightscope-installer.nsi"
if %errorlevel% equ 0 (
    echo Build completed successfully!
    echo Fixed installer created at: C:\Users\Eric\Desktop\thelightscope\windows-output\LightScope-0.0.102-Setup-Fixed.exe
) else (
    echo Build failed with error code %errorlevel%
)
pause 