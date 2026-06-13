!define APPNAME "chibi-scheme"
!define DESCRIPTION "Minimal Scheme Implementation for use as an Extension Language"

# These three must be integers
!define VERSIONMAJOR 0
!define VERSIONMINOR 12
!define VERSIONBUILD 0

# These will be displayed by the "Click here for support information" link in "Add/Remove Programs"
!define HELPURL "https://synthcode.com/scheme/chibi/" # "Support Information" link
!define UPDATEURL "https://github.com/ashinn/chibi-scheme" # "Product Updates" link

RequestExecutionLevel admin ;Require admin rights on NT6+ (When UAC is turned on)

InstallDir "$PROGRAMFILES\${APPNAME}"

# rtf or txt file - remember if it is txt, it must be in the DOS text format (\r\n)
LicenseData "COPYING"

# This will be in the installer/uninstaller's title bar
Name "${APPNAME}"
outFile "setup_chibi-scheme.exe"

!include LogicLib.nsh

# Just three pages - license agreement, install location, and installation
page license
page directory
Page instfiles

!macro VerifyUserIsAdmin
UserInfo::GetAccountType
pop $0
${If} $0 != "admin" ;Require admin rights on NT4+
        messageBox mb_iconstop "Administrator rights required!"
        setErrorLevel 740 ;ERROR_ELEVATION_REQUIRED
        quit
${EndIf}
!macroend

function .onInit
	setShellVarContext all
	!insertmacro VerifyUserIsAdmin
functionEnd

section "install"
	# Files for the install directory - to build the installer, these should be in the same directory as the install script (this file)
	setOutPath $INSTDIR

	# Files added here should be removed by the uninstaller (see section "uninstall")
	file "chibi-scheme.exe"
	file "libchibi-scheme.dll.0.12.0"
	file "msys-2.0.dll"

	# Add any other files for the install directory (license files, app data, etc) here

	# Uninstaller - See function un.onInit and section "uninstall" for configuration
	writeUninstaller "$INSTDIR\uninstall_chibi-scheme.exe"

	createDirectory "$SMPROGRAMS\${APPNAME}"
	createShortCut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "cmd.exe" "$INSTDIR\chibi-scheme.exe" ""
 
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "DisplayName" "${APPNAME} - ${APPNAME} - ${DESCRIPTION}"
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "UninstallString" "$\"$INSTDIR\uninstall_chibi-scheme.exe$\""
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "QuietUninstallString" "$\"$INSTDIR\uninstall_chibi-scheme.exe$\" /S"
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "InstallLocation" "$\"$INSTDIR$\""
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "Publisher" "$\"${APPNAME}$\""
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "HelpLink" "$\"${HELPURL}$\""
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "URLUpdateInfo" "$\"${UPDATEURL}$\""
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "DisplayVersion" "$\"${VERSIONMAJOR}.${VERSIONMINOR}.${VERSIONBUILD}$\""
	WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "VersionMajor" ${VERSIONMAJOR}
	WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "VersionMinor" ${VERSIONMINOR}
	# There is no option for modifying or repairing the install
	WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "NoModify" 1
	WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}" "NoRepair" 1
sectionEnd

# Uninstaller

function un.onInit
	SetShellVarContext all

	#Verify the uninstaller - last chance to back out
	MessageBox MB_OKCANCEL "Permanently remove ${APPNAME}?" IDOK next
		Abort
	next:
	!insertmacro VerifyUserIsAdmin
functionEnd

section "uninstall"

	# Remove Start Menu launcher
	delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
	# Try to remove the Start Menu folder - this will only happen if it is empty
	rmDir "$SMPROGRAMS\${APPNAME}"

	# Remove files
	delete $INSTDIR\chibi-scheme.exe
	delete $INSTDIR\libchibi-scheme.dll.0.12.0
	delete $INSTDIR\msys-2.0.dll

	# Always delete uninstaller as the last action
	delete $INSTDIR\uninstall_chibi-scheme.exe

	# Try to remove the install directory - this will only happen if it is empty
	rmDir $INSTDIR

	# Remove uninstaller information from the registry
	DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME} ${APPNAME}"
sectionEnd