# PS4 Theme Creator

A companion app for designing personal PS4 themes, organizing wallpaper and audio assets, and preparing theme projects for transfer to a PS4.

## Current foundation
- Flutter Android app shell with Create, Transfer, and Library sections
- Select a wallpaper image and optional background audio from local storage
- Save a theme draft locally and export its project manifest as JSON
- Clear separation between theme authoring and PS4 package generation

## Planned milestones
1. Theme editor: wallpaper, theme name, author, and sound asset selection.
2. Android-to-PS4 transfer: local-network receiver workflow with an explicit destination folder on the console.
3. PS4 theme package pipeline: validate the required theme layout and metadata, then build only with compatible, legally obtained tools.
4. Install and compatibility checks on supported PS4 firmware.

## Important compatibility note
A JSON project manifest is **not** an installable PS4 PKG. PS4 theme packages have platform-specific requirements. Package generation will only be marked ready after the output structure and build process are verified on real compatible hardware.

Use only images and audio you own or are authorized to use. This project does not include Sony proprietary SDKs or copyrighted theme assets.

## Build
The Android build is configured through GitHub Actions. Open **Actions → Android Build** to download the generated APK when a workflow run completes.

## Using the transfer screen

1. Start the FTP server from GoldHEN on the PS4.
2. Connect the Android phone and PS4 to the same local Wi-Fi network.
3. Enter the PS4 LAN IP address and the FTP port shown by the console.
4. Select a wallpaper and/or audio file on the Create tab.
5. Open Transfer and send the files. The app attempts to create `/data/PS4ThemeCreator/` and uploads the selected files plus `theme-project.json`.

FTP credentials and writable paths vary by server configuration. The app currently uses passive FTP and does not provide encryption; use it only on a trusted local network. If the PS4 FTP server does not permit writes to `/data`, the transfer will report the server error rather than silently claiming success.
